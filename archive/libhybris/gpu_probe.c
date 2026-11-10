/* gpu_probe.c — 原生 Arch GPU 通路探针（无 libhybris，纯内核 UAPI）
 * 验证：1) /dev/kgsl-3d0 可打开  2) dma-heap 分配  3) msm_drm PRIME 导入/导出
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mman.h>

struct dma_heap_allocation_data {
    uint64_t len;
    uint32_t fd;
    uint32_t fd_flags;
    uint64_t heap_flags;
};
#define DMA_HEAP_IOC_MAGIC 'H'
#define DMA_HEAP_IOCTL_ALLOC _IOWR(DMA_HEAP_IOC_MAGIC, 0, struct dma_heap_allocation_data)

#define DRM_IOCTL_BASE 'd'
#define DRM_IOWR(nr, type) _IOWR(DRM_IOCTL_BASE, nr, type)
struct drm_prime_handle {
    uint32_t handle;
    uint32_t flags;
    int32_t fd;
};
struct drm_mode_create_dumb {
    uint32_t height;
    uint32_t width;
    uint32_t bpp;
    uint32_t flags;
    uint32_t handle;
    uint32_t pitch;
    uint64_t size;
};
#define DRM_IOCTL_PRIME_FD_TO_HANDLE DRM_IOWR(0x2e, struct drm_prime_handle)
#define DRM_IOCTL_PRIME_HANDLE_TO_FD DRM_IOWR(0x2d, struct drm_prime_handle)
#define DRM_IOCTL_MODE_CREATE_DUMB   DRM_IOWR(0xB2, struct drm_mode_create_dumb)

static void readfile(const char *p, char *out, size_t n) {
    out[0] = 0;
    int fd = open(p, O_RDONLY);
    if (fd < 0) return;
    ssize_t r = read(fd, out, n - 1);
    close(fd);
    if (r > 0) { out[r] = 0; char *q = strchr(out, '\n'); if (q) *q = 0; }
}

int main(void) {
    char buf[128];

    /* 1) kgsl */
    int kgsl = open("/dev/kgsl-3d0", O_RDWR | O_CLOEXEC);
    printf("GPU-PROBE kgsl_open=%d errno=%d(%s)\n", kgsl, kgsl < 0 ? errno : 0, kgsl < 0 ? strerror(errno) : "ok");
    if (kgsl >= 0) close(kgsl);

    /* 2) dma-heap alloc */
    int heap = open("/dev/dma_heap/qcom,system", O_RDONLY | O_CLOEXEC);
    printf("GPU-PROBE heap_open=%d errno=%d\n", heap, heap < 0 ? errno : 0);
    if (heap >= 0) {
        struct dma_heap_allocation_data a;
        memset(&a, 0, sizeof(a));
        a.len = 1024 * 1024;
        a.fd_flags = O_RDWR | O_CLOEXEC;
        int rc = ioctl(heap, DMA_HEAP_IOCTL_ALLOC, &a);
        printf("GPU-PROBE heap_alloc rc=%d errno=%d(%s) fd=%u\n", rc, rc < 0 ? errno : 0,
               rc < 0 ? strerror(errno) : "ok", a.fd);
        if (rc == 0) {
            struct stat st;
            if (fstat((int)a.fd, &st) == 0)
                printf("GPU-PROBE dmabuf_size=%lld\n", (long long)st.st_size);

            /* 3a) dma-buf -> DRM import (PRIME_FD_TO_HANDLE) */
            const char *cards[] = {"/dev/dri/card0", "/dev/dri/renderD128"};
            for (int i = 0; i < 2; i++) {
                int card = open(cards[i], O_RDWR | O_CLOEXEC);
                if (card < 0) { printf("GPU-PROBE open %s fail errno=%d\n", cards[i], errno); continue; }
                struct drm_prime_handle ph;
                memset(&ph, 0, sizeof(ph));
                ph.fd = a.fd;
                ph.flags = 0;
                int rc2 = ioctl(card, DRM_IOCTL_PRIME_FD_TO_HANDLE, &ph);
                printf("GPU-PROBE prime_import(%s) rc=%d errno=%d(%s) gem_handle=%u\n",
                       cards[i], rc2, rc2 < 0 ? errno : 0, rc2 < 0 ? strerror(errno) : "ok", ph.handle);

                /* 3b) dumb create + export */
                struct drm_mode_create_dumb cd;
                memset(&cd, 0, sizeof(cd));
                cd.width = 256; cd.height = 256; cd.bpp = 32;
                int rc3 = ioctl(card, DRM_IOCTL_MODE_CREATE_DUMB, &cd);
                printf("GPU-PROBE dumb_create rc=%d errno=%d handle=%u pitch=%u size=%llu\n",
                       rc3, rc3 < 0 ? errno : 0, cd.handle, cd.pitch, (unsigned long long)cd.size);
                if (rc3 == 0) {
                    struct drm_prime_handle pe;
                    memset(&pe, 0, sizeof(pe));
                    pe.handle = cd.handle;
                    pe.flags = 0;
                    int rc4 = ioctl(card, DRM_IOCTL_PRIME_HANDLE_TO_FD, &pe);
                    printf("GPU-PROBE prime_export rc=%d errno=%d fd=%d\n", rc4, rc4 < 0 ? errno : 0, pe.fd);
                    if (rc4 == 0) close(pe.fd);
                }
                close(card);
            }
            close((int)a.fd);
        }
        close(heap);
    }

    readfile("/sys/class/kgsl/kgsl-3d0/gpu_model", buf, sizeof(buf));
    printf("GPU-PROBE gpu_model=%s\n", buf);
    readfile("/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq", buf, sizeof(buf));
    printf("GPU-PROBE gpu_cur_freq=%s\n", buf);
    printf("GPU-PROBE DONE\n");
    return 0;
}

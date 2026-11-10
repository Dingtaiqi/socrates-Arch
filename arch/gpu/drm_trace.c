/* RETIRED DIAGNOSTIC -- DO NOT PRELOAD INTO WESTON.
 * RTLD_NEXT failed to resolve symbols from Weston's RTLD_LOCAL backend
 * dependencies. Its ENOSYS fallback introduced an artificial device-opening
 * failure. Retained to explain the invalid early trace runs; use the direct
 * queries and uninstrumented baseline documented in README.md instead.
 * Build: aarch64-linux-gnu-gcc -shared -fPIC -O2 -Wall -Wextra -Werror
 *        -o libdrm_trace.so drm_trace.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>

struct resource_query {
    uint64_t fb_ptr, crtc_ptr, connector_ptr, encoder_ptr;
    uint32_t fbs, crtcs, connectors, encoders;
    uint32_t min_width, max_width, min_height, max_height;
};
_Static_assert(sizeof(struct resource_query) == 64, "DRM resources ABI");

void *drmModeGetResources(int fd)
{
    void *(*next)(int) = dlsym(RTLD_NEXT, "drmModeGetResources");
    if (!next) { errno = ENOSYS; return NULL; }
    void *result = next(fd);
    int saved = errno;
    struct resource_query q = {0};
    int rc = ioctl(fd, _IOWR('d', 0xa0, struct resource_query), &q);
    int query_errno = errno;
    fprintf(stderr, "[dsu-drm] drmModeGetResources fd=%d result=%p errno=%d; raw_rc=%d raw_errno=%d crtcs=%u connectors=%u encoders=%u\n",
            fd, result, result ? 0 : saved, rc, rc < 0 ? query_errno : 0,
            q.crtcs, q.connectors, q.encoders);
    errno = saved;
    return result;
}

int drmGetCap(int fd, uint64_t capability, uint64_t *value)
{
    int (*next)(int, uint64_t, uint64_t *) = dlsym(RTLD_NEXT, "drmGetCap");
    if (!next) { errno = ENOSYS; return -1; }
    int rc = next(fd, capability, value);
    int saved = errno;
    fprintf(stderr, "[dsu-drm] drmGetCap fd=%d cap=%llu rc=%d errno=%d value=%llu\n",
            fd, (unsigned long long)capability, rc, rc < 0 ? saved : 0,
            (unsigned long long)(rc == 0 && value ? *value : 0));
    errno = saved;
    return rc;
}

struct libseat;
int libseat_open_device(struct libseat *seat, const char *path, int *fd)
{
    int (*next)(struct libseat *, const char *, int *) = dlsym(RTLD_NEXT, "libseat_open_device");
    if (!next) { errno = ENOSYS; return -1; }
    int rc = next(seat, path, fd);
    int saved = errno;
    fprintf(stderr, "[dsu-drm] libseat_open_device path=%s rc=%d errno=%d fd=%d\n",
            path ? path : "(null)", rc, rc < 0 ? saved : 0, rc >= 0 && fd ? *fd : -1);
    errno = saved;
    return rc;
}

int drmSetMaster(int fd)
{
    int (*next)(int) = dlsym(RTLD_NEXT, "drmSetMaster");
    if (!next) { errno = ENOSYS; return -1; }
    int rc = next(fd);
    int saved = errno;
    fprintf(stderr, "[dsu-drm] drmSetMaster fd=%d rc=%d errno=%d\n", fd, rc, rc < 0 ? saved : 0);
    errno = saved;
    return rc;
}

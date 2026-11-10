/* Bounded diagnostic for KGSL render-only GBM buffers on the vendor KMS node.
 * Preserve valid handles. If Mesa exposes no KMS handle, import the actual
 * exported DMA-BUF into this GBM device's DRM file. No pixels/formats/modifiers
 * or ioctl results are fabricated. Imported GEM handles live until process
 * exit/DRM-file close; this is not a production lifetime-management fix.
 */
#define _GNU_SOURCE
#include <gbm.h>
#include <xf86drm.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane)
{
    void *lib = dlopen("libgbm.so.1", RTLD_NOW | RTLD_LOCAL);
    union gbm_bo_handle invalid = {.u64 = UINT64_MAX};
    if (!lib) {
        fprintf(stderr, "[kgsl-gbm] cannot resolve actual libgbm: %s\n", dlerror());
        errno = ENOSYS;
        return invalid;
    }
    union gbm_bo_handle (*original)(struct gbm_bo *, int) =
        dlsym(lib, "gbm_bo_get_handle_for_plane");
    if (!original) {
        fprintf(stderr, "[kgsl-gbm] actual GBM entry point missing\n");
        dlclose(lib);
        errno = ENOSYS;
        return invalid;
    }
    union gbm_bo_handle handle = original(bo, plane);
    int saved = errno;
    dlclose(lib);
    if (handle.u32 != 0 && handle.u32 != UINT32_MAX) {
        errno = saved;
        return handle;
    }
    int dmabuf = gbm_bo_get_fd_for_plane(bo, plane);
    if (dmabuf < 0) {
        fprintf(stderr, "[kgsl-gbm] original=%u DMA-BUF export failed errno=%d\n", handle.u32, errno);
        return handle;
    }
    int drmfd = gbm_device_get_fd(gbm_bo_get_device(bo));
    uint32_t imported = 0;
    int rc = drmPrimeFDToHandle(drmfd, dmabuf, &imported);
    saved = errno;
    fprintf(stderr, "[kgsl-gbm] original=%u plane=%d drmfd=%d dmabuf=%d import_rc=%d handle=%u errno=%d\n",
            handle.u32, plane, drmfd, dmabuf, rc, imported, rc ? saved : 0);
    close(dmabuf);
    errno = saved;
    if (!rc) handle.u32 = imported;
    return handle;
}

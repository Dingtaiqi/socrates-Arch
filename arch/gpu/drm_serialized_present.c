/* Bounded socrates diagnostic: retain the driver's advertised serialized
 * command-mode frame trigger policy in KWin's own atomic requests. The policy
 * reverted across KWin startup in testing, so setting it before KWin was not
 * sufficient. No completion events, capabilities or pixel formats are faked.
 */
#define _GNU_SOURCE
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t find_policy(int fd)
{
    drmModeConnector *c = drmModeGetConnector(fd, 65);
    if (!c) return 0;
    int matches = c->connector_type == DRM_MODE_CONNECTOR_DSI
        && c->connector_type_id == 1;
    drmModeFreeConnector(c);
    if (!matches) return 0;
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, 65, DRM_MODE_OBJECT_CONNECTOR);
    if (!props) return 0;
    uint32_t id = 0;
    for (uint32_t i = 0; i < props->count_props; ++i) {
        drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);
        if (!p) continue;
        if (!strcmp(p->name, "frame_trigger_mode")) {
            for (int j = 0; j < p->count_enums; ++j) {
                if (p->enums[j].value == 1 && !strcmp(p->enums[j].name, "serialize_frame_trigger")) id = p->prop_id;
            }
        }
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(props);
    return id;
}

int drmIoctl(int fd, unsigned long request, void *arg)
{
    void *lib = dlopen("libdrm.so.2", RTLD_NOW | RTLD_LOCAL);
    if (!lib) { errno = ENOSYS; return -1; }
    int (*original)(int, unsigned long, void *) = dlsym(lib, "drmIoctl");
    if (!original) { dlclose(lib); errno = ENOSYS; return -1; }
    static _Thread_local int cached_fd = -1;
    static _Thread_local uint32_t property;
    static _Thread_local unsigned logged;
    static _Thread_local int bypass;
    if (request != DRM_IOCTL_MODE_ATOMIC || bypass || !getenv("SOCRATES_SERIALIZED_PRESENT")) {
        int rc = original(fd, request, arg);
        int saved = errno;
        dlclose(lib); errno = saved; return rc;
    }
    const struct drm_mode_atomic *input = arg;
    int (*commit)(int, drmModeAtomicReq *, uint32_t, void *) = dlsym(lib, "drmModeAtomicCommit");
    if (!commit || input->reserved || input->count_objs > 128) {
        int rc = original(fd, request, arg);
        int saved = errno;
        dlclose(lib); errno = saved; return rc;
    }
    bypass = 1;
    drmModeAtomicReq *copy = NULL;
    {
        if (cached_fd != fd) {
            property = find_policy(fd);
            cached_fd = fd;
            fprintf(stderr, "[serialized-present] fd=%d verified DSI-1 property=%u\n", fd, property);
        }
        if (property) {
            copy = drmModeAtomicAlloc();
            if (!copy) goto allocation_failed;
            const uint32_t *objects = (void *)(uintptr_t)input->objs_ptr;
            const uint32_t *counts = (void *)(uintptr_t)input->count_props_ptr;
            const uint32_t *ids = (void *)(uintptr_t)input->props_ptr;
            const uint64_t *values = (void *)(uintptr_t)input->prop_values_ptr;
            size_t index = 0;
            for (uint32_t i = 0; i < input->count_objs; ++i) {
                if (counts[i] > 1024 || index + counts[i] > 4096) goto allocation_failed;
                for (uint32_t j = 0; j < counts[i]; ++j, ++index) {
                    if (drmModeAtomicAddProperty(copy, objects[i], ids[index], values[index]) < 0) goto allocation_failed;
                }
            }
            if (drmModeAtomicAddProperty(copy, 65, property, 1) < 0) goto allocation_failed;
        }
    }
    int rc = copy ? commit(fd, copy, input->flags, (void *)(uintptr_t)input->user_data) : original(fd, request, arg);
    int saved = errno;
    if (copy && (logged < 8 || rc)) {
        fprintf(stderr, "[serialized-present] flags=0x%x rc=%d errno=%d\n", input->flags, rc, rc ? saved : 0);
        ++logged;
    }
    if (copy) drmModeAtomicFree(copy);
    bypass = 0;
    dlclose(lib); errno = saved; return rc;
allocation_failed:
    if (copy) drmModeAtomicFree(copy);
    bypass = 0;
    dlclose(lib); errno = ENOMEM; return -1;
}

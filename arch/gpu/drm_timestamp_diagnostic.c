/* Diagnostic timestamp fallback for zero/non-increasing vendor flip times.
 * Single-output socrates diagnostic. Event arrival CLOCK_MONOTONIC is an
 * estimate, not a hardware timestamp. Preserve increasing driver timestamps.
 */
#define _GNU_SOURCE
#include <xf86drm.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static _Thread_local drmEventContextPtr current;
static unsigned logged;
static unsigned long long previous_report;

static void timestamp(unsigned *sec, unsigned *usec)
{
    if (logged < 4) {
        fprintf(stderr, "[drm-timestamp] driver sec=%u usec=%u\n", *sec, *usec);
        logged++;
    }
    unsigned long long report = (unsigned long long)*sec * 1000000 + *usec;
    int invalid = report == 0 || report <= previous_report;
    previous_report = report;
    if (invalid && getenv("SOCRATES_EVENT_TIMESTAMP_FALLBACK")) {
        struct timespec now;
        if (!clock_gettime(CLOCK_MONOTONIC, &now)) {
            *sec = (unsigned)now.tv_sec;
            *usec = (unsigned)(now.tv_nsec / 1000);
        }
    }
}
static void pageflip(int fd, unsigned seq, unsigned sec, unsigned usec, void *data)
{
    timestamp(&sec, &usec);
    current->page_flip_handler(fd, seq, sec, usec, data);
}
static void pageflip2(int fd, unsigned seq, unsigned sec, unsigned usec, unsigned crtc, void *data)
{
    timestamp(&sec, &usec);
    current->page_flip_handler2(fd, seq, sec, usec, crtc, data);
}
int drmHandleEvent(int fd, drmEventContextPtr ctx)
{
    void *lib = dlopen("libdrm.so.2", RTLD_NOW | RTLD_LOCAL);
    if (!lib) { errno = ENOSYS; return -1; }
    int (*original)(int, drmEventContextPtr) = dlsym(lib, "drmHandleEvent");
    if (!original) { dlclose(lib); errno = ENOSYS; return -1; }
    drmEventContext wrapped = {0};
    wrapped.version = ctx->version;
    wrapped.vblank_handler = ctx->vblank_handler;
    if (ctx->version >= 2 && ctx->page_flip_handler) wrapped.page_flip_handler = pageflip;
    if (ctx->version >= 3 && ctx->page_flip_handler2) wrapped.page_flip_handler2 = pageflip2;
    if (ctx->version >= 4) wrapped.sequence_handler = ctx->sequence_handler;
    drmEventContextPtr previous = current;
    current = ctx;
    int rc = original(fd, &wrapped);
    int saved = errno;
    current = previous;
    dlclose(lib);
    errno = saved;
    return rc;
}

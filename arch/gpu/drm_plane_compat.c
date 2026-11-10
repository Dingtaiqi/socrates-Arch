/* Temporary Weston compatibility test for socrates' vendor DRM driver.
 * The driver reports repeated fourcc values in GETPLANE. Remove only exact
 * repetitions, retaining order and every unique format. No capability, mode,
 * modifier blob, ioctl result or buffer operation is fabricated.
 * Resolve through an explicit libdrm handle: RTLD_NEXT cannot reliably find
 * dependencies loaded in Weston's RTLD_LOCAL backend scope.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct plane {
    uint32_t count; uint32_t *formats;
    uint32_t id, crtc, fb, cx, cy, x, y, possible, gamma;
};

struct plane *drmModeGetPlane(int fd, uint32_t id)
{
    void *h=dlopen("libdrm.so.2",RTLD_NOW|RTLD_LOCAL);
    if (!h) { fprintf(stderr,"[plane-compat] libdrm: %s\n",dlerror()); errno=ENOSYS;return NULL; }
    struct plane *(*original)(int,uint32_t)=dlsym(h,"drmModeGetPlane");
    if (!original) { dlclose(h); errno=ENOSYS;return NULL; }
    struct plane *p=original(fd,id);
    int saved=errno;
    if (p) {
        uint32_t n=0,old=p->count;
        for (uint32_t i=0;i<old;i++) {
            uint32_t j;
            for (j=0;j<n;j++) if (p->formats[j]==p->formats[i]) break;
            if (j==n) p->formats[n++]=p->formats[i];
        }
        p->count=n;
        if (n!=old) fprintf(stderr,"[plane-compat] plane=%u formats=%u unique=%u\n",id,old,n);
        /* Diagnostic format restriction: select only an already advertised
         * opaque XRGB8888 format. Never add or reinterpret a format. */
        if (getenv("SOCRATES_DIAGNOSTIC_XRGB8888")) {
            const uint32_t xr24 = (uint32_t)'X' | ((uint32_t)'R' << 8)
                | ((uint32_t)'2' << 16) | ((uint32_t)'4' << 24);
            for (uint32_t i=0; i<n; i++) {
                if (p->formats[i] == xr24) {
                    p->formats[0]=xr24; p->count=1;
                    fprintf(stderr,"[plane-compat] plane=%u restrict to advertised XRGB8888\n",id);
                    break;
                }
            }
        }
    }
    dlclose(h);errno=saved;return p;
}

/* Diagnostic-only routing restriction, opt-in for this verified device.
 * Its boot splash reserves plane 77 on resource-index 0 / CRTC 167, while
 * the encoder reports no current CRTC. Never add an unsupported route.
 */
struct encoder { uint32_t id, type, crtc, possible_crtcs, possible_clones; };
struct encoder *drmModeGetEncoder(int fd, uint32_t id)
{
    void *h=dlopen("libdrm.so.2",RTLD_NOW|RTLD_LOCAL);
    if (!h) { errno=ENOSYS; return NULL; }
    struct encoder *(*original)(int,uint32_t)=dlsym(h,"drmModeGetEncoder");
    if (!original) { dlclose(h); errno=ENOSYS; return NULL; }
    struct encoder *e=original(fd,id);
    int saved=errno;
    if(e && id==64 && getenv("SOCRATES_DIAGNOSTIC_CRTC0") && (e->possible_crtcs&1)) {
        fprintf(stderr,"[plane-compat] DSI encoder=%u crtc=%u route mask 0x%x -> 0x1\n",id,e->crtc,e->possible_crtcs);
        e->possible_crtcs=1;
    }
    dlclose(h);errno=saved;return e;
}

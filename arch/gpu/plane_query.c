#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

struct planes { uint32_t count; uint32_t *ids; };
struct plane { uint32_t count; uint32_t *formats; uint32_t id, crtc, fb, cx, cy, x, y, possible, gamma; };

int main(void) {
    void *h=dlopen("libdrm.so.2",RTLD_NOW);
    if (!h) return 1;
    int (*cap)(int,uint64_t,uint64_t)=dlsym(h,"drmSetClientCap");
    struct planes *(*getplanes)(int)=dlsym(h,"drmModeGetPlaneResources");
    struct plane *(*getplane)(int,uint32_t)=dlsym(h,"drmModeGetPlane");
    void (*freeplane)(struct plane*)=dlsym(h,"drmModeFreePlane");
    void (*freeplanes)(struct planes*)=dlsym(h,"drmModeFreePlaneResources");
    if (!cap || !getplanes || !getplane || !freeplane || !freeplanes) return 2;
    int fd=open("/dev/dri/card0",O_RDONLY|O_CLOEXEC);
    if (fd<0) return 3;
    printf("UNIVERSAL_PLANES rc=%d\n",cap(fd,2,1));
    struct planes *ps=getplanes(fd);
    if (!ps) return 4;
    printf("PLANES=%u\n",ps->count);
    for (uint32_t i=0;i<ps->count;i++) {
        struct plane *p=getplane(fd,ps->ids[i]);
        if (!p) continue;
        uint32_t dup=0;
        printf("plane=%u possible=0x%x formats=%u ",p->id,p->possible,p->count);
        for (uint32_t j=0;j<p->count;j++) {
            for (uint32_t k=0;k<j;k++) if(p->formats[j]==p->formats[k]) {
                uint32_t f=p->formats[j];
                printf("duplicate[%u]=%c%c%c%c ",j,f&255,(f>>8)&255,(f>>16)&255,(f>>24)&255);
                dup++;break;
            }
        }
        printf("duplicate_count=%u\n",dup);
        freeplane(p);
    }
    freeplanes(ps);close(fd);return 0;
}

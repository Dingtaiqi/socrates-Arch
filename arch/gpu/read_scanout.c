/* Historical dumb-buffer probe. DO NOT run against a GPU/imported framebuffer.
 * A DSU reboot followed a GETFB/MAP_DUMB read of a KGSL-imported scanout buffer
 * on 2026-11-09. Causation is unconfirmed; no pstore survived. This tool is
 * retained as evidence of the earlier Pixman-only capture, not a GPU capturer.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
struct crtc { uint32_t id, fb, x,y,w,h; int valid; };
struct fb { uint32_t id,w,h,pitch,bpp,depth,handle; };
struct map_dumb { uint32_t handle,pad; uint64_t offset; };
int main(void) {
    void *h=dlopen("libdrm.so.2",RTLD_NOW);
    if(!h)return 1;
    struct crtc *(*getcrtc)(int,uint32_t)=dlsym(h,"drmModeGetCrtc");
    struct fb *(*getfb)(int,uint32_t)=dlsym(h,"drmModeGetFB");
    int fd=open("/dev/dri/card0",O_RDWR|O_CLOEXEC);
    if(fd<0)return 2;
    struct crtc *c=getcrtc(fd,167);
    if(!c){perror("getcrtc");return 3;}
    fprintf(stderr,"crtc=%u fb=%u size=%ux%u valid=%d\n",c->id,c->fb,c->w,c->h,c->valid);
    struct fb *f=getfb(fd,c->fb);
    if(!f){perror("getfb");return 4;}
    fprintf(stderr,"fb=%u size=%ux%u pitch=%u bpp=%u depth=%u handle=%u\n",f->id,f->w,f->h,f->pitch,f->bpp,f->depth,f->handle);
    if(f->bpp!=32 || !f->w || !f->h || f->h>8192 || f->pitch>65536)return 5;
    struct map_dumb m={.handle=f->handle};
    if(ioctl(fd,_IOWR('d',0xb3,struct map_dumb),&m)){perror("mapdumb");return 6;}
    unsigned char *p=mmap(NULL,(size_t)f->pitch*f->h,PROT_READ,MAP_SHARED,fd,m.offset);
    if(p==MAP_FAILED){perror("mmap");return 7;}
    FILE *out=fopen("/dev/kde_dsu/scanout.ppm","wb");
    if(!out)return 8;
    const uint32_t step=8,w=f->w/step,hh=f->h/step;
    fprintf(out,"P6\n%u %u\n255\n",w,hh);
    for(uint32_t y=0;y<hh;y++)for(uint32_t x=0;x<w;x++) {
        unsigned char *px=p+(size_t)y*step*f->pitch+x*step*4;
        unsigned char rgb[3]={px[2],px[1],px[0]};
        fwrite(rgb,1,3,out);
    }
    fclose(out);munmap(p,(size_t)f->pitch*f->h);close(fd);return 0;
}

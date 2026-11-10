#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
int main(void) {
    void *h=dlopen("libudev.so.1",RTLD_NOW);
    if(!h){fprintf(stderr,"%s\n",dlerror());return 1;}
    void *(*new_udev)(void)=dlsym(h,"udev_new");
    void *(*new_device)(void*,const char*,const char*)=dlsym(h,"udev_device_new_from_subsystem_sysname");
    void *ctx=new_udev(), *dev=new_device(ctx,"drm","card0");
    printf("udev=%p device=%p errno=%d\n",ctx,dev,errno);
    if(!dev)return 2;
    const char *names[]={"udev_device_get_devnode","udev_device_get_syspath","udev_device_get_sysname","udev_device_get_sysnum","udev_device_get_devtype"};
    for(unsigned i=0;i<sizeof(names)/sizeof(names[0]);++i){
        const char *(*fn)(void*)=dlsym(h,names[i]);
        const char *value=fn(dev);
        printf("%s=%s errno=%d\n",names[i],value?value:"NULL",errno);
    }
    unsigned long (*getnum)(void*)=dlsym(h,"udev_device_get_devnum");
    printf("devnum=%lu\n",getnum(dev));
    h=dlopen("libdrm.so.2",RTLD_NOW);
    if(!h){fprintf(stderr,"%s\n",dlerror());return 3;}
    void *(*getresources)(int)=dlsym(h,"drmModeGetResources");
    void (*freeresources)(void*)=dlsym(h,"drmModeFreeResources");
    int fd=open("/dev/dri/card0",O_RDONLY|O_CLOEXEC);
    void *res=getresources(fd);
    printf("libdrm resources=%p errno=%d fd=%d\n",res,errno,fd);
    if(res)freeresources(res);
    if(fd>=0)close(fd);
    return res?0:4;
}

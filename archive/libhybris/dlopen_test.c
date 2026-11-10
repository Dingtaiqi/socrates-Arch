#include <stdio.h>
#include <dlfcn.h>
#include <string.h>

extern void* android_dlopen(const char* filename, int flag);
extern void* android_dlsym(void* handle, const char* symbol);
extern char* android_dlerror(void);

int main(int argc, char** argv)
{
    const char* lib = argc > 1 ? argv[1] : "libEGL_adreno.so";
    void* h = android_dlopen(lib, RTLD_NOW);
    if (!h) {
        printf("DL-TEST-FAIL lib=%s err=%s\n", lib, android_dlerror());
        return 1;
    }
    printf("DL-TEST-OK lib=%s handle=%p\n", lib, h);
    void* sym = android_dlsym(h, argc > 2 ? argv[2] : "eglGetDisplay");
    printf("DL-TEST-SYM %s=%p\n", argc > 2 ? argv[2] : "eglGetDisplay", sym);
    return 0;
}

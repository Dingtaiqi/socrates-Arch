#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef void *EGLDisplay;
typedef int32_t EGLint;
typedef intptr_t EGLAttrib;
typedef unsigned int EGLenum;

extern EGLDisplay eglGetDisplay(void *);
extern EGLDisplay eglGetPlatformDisplay(EGLenum, void *, const EGLAttrib *);
extern EGLint eglInitialize(EGLDisplay, EGLint *, EGLint *);
extern const char *eglQueryString(EGLDisplay, EGLint);
extern EGLint eglGetError(void);

#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_EXTENSIONS 0x3055
#define EGL_VERSION 0x3054
#define EGL_VENDOR 0x3053
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD

int main(void)
{
    printf("client ext: %s\n", eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS));
    EGLDisplay d = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, (void *)0, 0);
    printf("eglGetPlatformDisplay(SURFACELESS) = %p err=0x%x\n", d, eglGetError());
    if (d == EGL_NO_DISPLAY) {
        d = eglGetDisplay((void *)0);
        printf("fallback eglGetDisplay = %p err=0x%x\n", d, eglGetError());
    }
    if (d == EGL_NO_DISPLAY) return 1;
    EGLint maj = 0, min = 0;
    EGLint ok = eglInitialize(d, &maj, &min);
    printf("eglInitialize=%d (%d.%d) err=0x%x\n", ok, maj, min, eglGetError());
    printf("EGL_VERSION=%s EGL_VENDOR=%s\n",
           eglQueryString(d, EGL_VERSION), eglQueryString(d, EGL_VENDOR));
    printf("display ext: %s\n", eglQueryString(d, EGL_EXTENSIONS));
    return ok ? 0 : 2;
}

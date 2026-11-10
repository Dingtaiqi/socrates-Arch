/* libwsglfix.so v2 — weston surfaceless interposer
 *  - eglQueryString(EGL_NO_DISPLAY) 追加 EGL_MESA_platform_surfaceless / EGL_EXT_platform_base
 *  - eglGetPlatformDisplay(SURFACELESS_MESA) → eglGetDisplay(EGL_DEFAULT_DISPLAY)
 *  - 提供 eglCreatePlatformWindowSurface[EXT]（weston egl-glue 断言需要该函数指针）
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

typedef void *EGLDisplay;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef void *EGLConfig;
typedef int32_t EGLint;
typedef intptr_t EGLAttrib;
typedef unsigned int EGLenum;
typedef void *EGLNativeDisplayType;
typedef void *EGLNativeWindowType;

#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_EXTENSIONS 0x3055
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#define EGL_NO_SURFACE ((EGLSurface)0)

static void *(*real_eglGetProcAddress)(const char *);
static EGLDisplay (*real_eglGetDisplay)(EGLNativeDisplayType);
static EGLDisplay (*real_eglGetPlatformDisplay)(EGLenum, void *, const EGLAttrib *);
static const char *(*real_eglQueryString)(EGLDisplay, EGLint);
static EGLSurface (*real_eglCreateWindowSurface)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *);
static EGLSurface (*real_eglCreatePlatformWindowSurface)(EGLDisplay, EGLConfig, void *, const EGLAttrib *);

static void resolve(void)
{
    if (!real_eglGetDisplay)
        real_eglGetDisplay = (EGLDisplay(*)(EGLNativeDisplayType))dlsym(RTLD_NEXT, "eglGetDisplay");
    if (!real_eglGetPlatformDisplay)
        real_eglGetPlatformDisplay = (EGLDisplay(*)(EGLenum, void *, const EGLAttrib *))dlsym(RTLD_NEXT, "eglGetPlatformDisplay");
    if (!real_eglQueryString)
        real_eglQueryString = (const char *(*)(EGLDisplay, EGLint))dlsym(RTLD_NEXT, "eglQueryString");
    if (!real_eglGetProcAddress)
        real_eglGetProcAddress = (void *(*)(const char *))dlsym(RTLD_NEXT, "eglGetProcAddress");
    if (!real_eglCreateWindowSurface)
        real_eglCreateWindowSurface = (EGLSurface(*)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *))dlsym(RTLD_NEXT, "eglCreateWindowSurface");
    if (!real_eglCreatePlatformWindowSurface)
        real_eglCreatePlatformWindowSurface = (EGLSurface(*)(EGLDisplay, EGLConfig, void *, const EGLAttrib *))dlsym(RTLD_NEXT, "eglCreatePlatformWindowSurface");
}

EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *display_id, const EGLAttrib *attrib_list)
{
    resolve();
    if (platform == EGL_PLATFORM_SURFACELESS_MESA) {
        if (real_eglGetDisplay)
            return real_eglGetDisplay((EGLNativeDisplayType)0);
        return EGL_NO_DISPLAY;
    }
    if (real_eglGetPlatformDisplay)
        return real_eglGetPlatformDisplay(platform, display_id, attrib_list);
    if (real_eglGetDisplay)
        return real_eglGetDisplay((EGLNativeDisplayType)display_id);
    return EGL_NO_DISPLAY;
}

EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform, void *display_id, const EGLint *attrib_list)
{
    return eglGetPlatformDisplay(platform, display_id, (const EGLAttrib *)attrib_list);
}

const char *eglQueryString(EGLDisplay dpy, EGLint name)
{
    resolve();
    const char *ret = real_eglQueryString ? real_eglQueryString(dpy, name) : NULL;
    if (dpy == EGL_NO_DISPLAY && name == EGL_EXTENSIONS) {
        static char buf[4096];
        snprintf(buf, sizeof(buf) - 1, "%s %s", ret ? ret : "",
                 "EGL_EXT_client_extensions EGL_EXT_platform_base "
                 "EGL_MESA_platform_surfaceless");
        return buf;
    }
    return ret;
}

EGLSurface eglCreatePlatformWindowSurface(EGLDisplay dpy, EGLConfig config, void *native_window, const EGLAttrib *attrib_list)
{
    resolve();
    if (real_eglCreatePlatformWindowSurface)
        return real_eglCreatePlatformWindowSurface(dpy, config, native_window, attrib_list);
    if (real_eglCreateWindowSurface)
        return real_eglCreateWindowSurface(dpy, config, (EGLNativeWindowType)native_window, (const EGLint *)attrib_list);
    return EGL_NO_SURFACE;
}

EGLSurface eglCreatePlatformWindowSurfaceEXT(EGLDisplay dpy, EGLConfig config, void *native_window, const EGLint *attrib_list)
{
    return eglCreatePlatformWindowSurface(dpy, config, native_window, (const EGLAttrib *)attrib_list);
}

__attribute__((visibility("default")))
void *eglGetProcAddress(const char *name)
{
    resolve();
    if (!name) return NULL;
    if (strcmp(name, "eglGetPlatformDisplay") == 0) return (void *)eglGetPlatformDisplay;
    if (strcmp(name, "eglGetPlatformDisplayEXT") == 0) return (void *)eglGetPlatformDisplayEXT;
    if (strcmp(name, "eglCreatePlatformWindowSurface") == 0) return (void *)eglCreatePlatformWindowSurface;
    if (strcmp(name, "eglCreatePlatformWindowSurfaceEXT") == 0) return (void *)eglCreatePlatformWindowSurfaceEXT;
    if (real_eglGetProcAddress)
        return real_eglGetProcAddress(name);
    return NULL;
}

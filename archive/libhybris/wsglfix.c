/* libwsglfix.so — weston surfaceless interposer
 * 让 hybris EGL（Android libEGL 转发）"看起来"支持 EGL_MESA_platform_surfaceless：
 *  - eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS) 追加 surfaceless/platform_base 扩展
 *  - eglGetPlatformDisplay(SURFACELESS_MESA) → 走 eglGetDisplay(EGL_DEFAULT_DISPLAY)
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

#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_EXTENSIONS 0x3055
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD

static void *(*real_eglGetProcAddress)(const char *);

static EGLDisplay (*real_eglGetDisplay)(EGLNativeDisplayType);
static EGLDisplay (*real_eglGetPlatformDisplay)(EGLenum, void *, const EGLAttrib *);
static const char *(*real_eglQueryString)(EGLDisplay, EGLint);

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

__attribute__((visibility("default")))
void *eglGetProcAddress(const char *name)
{
    resolve();
    if (name && strcmp(name, "eglGetPlatformDisplay") == 0)
        return (void *)eglGetPlatformDisplay;
    if (name && strcmp(name, "eglGetPlatformDisplayEXT") == 0)
        return (void *)eglGetPlatformDisplayEXT;
    if (real_eglGetProcAddress)
        return real_eglGetProcAddress(name);
    return NULL;
}

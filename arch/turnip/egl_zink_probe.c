/* Real EGL/GLES rendering probe: no capability shims or synthetic pixels.
 * Run with the staged KGSL ICD selected and Mesa's Zink driver override.
 * Passing requires an Adreno/Zink renderer and actual glReadPixels data.
 */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *stage)
{
    fprintf(stderr, "EGL_ZINK_FAIL stage=%s egl_error=0x%x\n", stage, eglGetError());
    exit(1);
}

int main(void)
{
    PFNEGLGETPLATFORMDISPLAYEXTPROC platform =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (!platform) fail("platform entry point");
    EGLDisplay d = platform(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    if (d == EGL_NO_DISPLAY) fail("surfaceless display");
    EGLint major, minor;
    if (!eglInitialize(d, &major, &minor)) fail("initialize");
    printf("EGL=%d.%d vendor=%s\n", major, minor, eglQueryString(d, EGL_VENDOR));
    if (!eglBindAPI(EGL_OPENGL_ES_API)) fail("bind GLES");
    const EGLint config_attrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig config;
    EGLint count = 0;
    if (!eglChooseConfig(d, config_attrs, &config, 1, &count) || count != 1)
        fail("choose config");
    const EGLint surface_attrs[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(d, config, surface_attrs);
    if (surface == EGL_NO_SURFACE) fail("pbuffer");
    const EGLint context_attrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext context = eglCreateContext(d, config, EGL_NO_CONTEXT, context_attrs);
    if (context == EGL_NO_CONTEXT) fail("context");
    if (!eglMakeCurrent(d, surface, surface, context)) fail("make current");
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("GL_RENDERER=%s\nGL_VERSION=%s\n", renderer ? renderer : "NULL", version ? version : "NULL");
    fflush(stdout);
    glClearColor(0.2f, 0.4f, 0.6f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    unsigned char pixel[4] = {0};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    GLenum error = glGetError();
    printf("PIXEL=%02x %02x %02x %02x GL_ERROR=0x%x\n", pixel[0], pixel[1], pixel[2], pixel[3], error);
    int pixel_ok = abs((int)pixel[0] - 51) <= 1 && abs((int)pixel[1] - 102) <= 1 &&
                   abs((int)pixel[2] - 153) <= 1 && pixel[3] == 255;
    int renderer_ok = renderer && strcasestr(renderer, "zink") && strcasestr(renderer, "adreno") &&
                      !strcasestr(renderer, "llvmpipe");
    const char *extensions = eglQueryString(d, EGL_EXTENSIONS);
    printf("EGL_DMABUF_IMPORT=%d\n", extensions && strstr(extensions, "EGL_EXT_image_dma_buf_import") != NULL);
    eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(d, context);
    eglDestroySurface(d, surface);
    eglTerminate(d);
    if (error != GL_NO_ERROR || !pixel_ok || !renderer_ok) {
        fprintf(stderr, "EGL_ZINK_FAIL pixel_ok=%d renderer_ok=%d\n", pixel_ok, renderer_ok);
        return 2;
    }
    puts("EGL_ZINK_ADRENO_PIXEL_PASS (offscreen only; does not prove desktop presentation)");
    return 0;
}

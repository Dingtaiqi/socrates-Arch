import re

p = '/root/ub-libhybris/hybris/egl/egl.c'
src = open(p).read()
marker = 'EGL_MESA_platform_surfaceless'
if marker in src:
    print('already patched')
else:
    anchor = '\treturn ws_eglQueryString(dpy, name, _eglQueryString);\n}'
    add = (
        '\t/* hybris: advertise client/platform extensions for glibc compositors\n'
        '\t * (weston headless gl-renderer checks EGL_MESA_platform_surfaceless) */\n'
        '\tif (dpy == EGL_NO_DISPLAY && name == EGL_EXTENSIONS && _eglQueryString) {\n'
        '\t\tconst char *real = _eglQueryString(dpy, name);\n'
        '\t\tstatic char egbuf[4096];\n'
        '\t\tsnprintf(egbuf, sizeof(egbuf) - 2, "%s %s", real ? real : "",\n'
        '\t\t\t"EGL_EXT_client_extensions EGL_EXT_platform_base "\n'
        '\t\t\t"EGL_MESA_platform_surfaceless");\n'
        '\t\treturn egbuf;\n'
        '\t}\n\n'
    )
    if anchor not in src:
        print('ANCHOR NOT FOUND')
    else:
        src = src.replace(anchor, add + anchor, 1)
        open(p, 'w').write(src)
        print('PATCHED eglQueryString')

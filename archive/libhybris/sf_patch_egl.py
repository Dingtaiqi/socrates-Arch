import sys

p = sys.argv[1] if len(sys.argv) > 1 else 'egl/egl.c'
src = open(p).read()

macro = (
    '#ifndef EGL_PLATFORM_SURFACELESS_MESA\n'
    '#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD\n'
    '#endif\n\n'
)

if 'EGL_PLATFORM_SURFACELESS_MESA' not in src:
    anchor = 'static const char * _defaultEglPlatform()'
    if anchor not in src:
        print('MISS anchor1'); sys.exit(1)
    src = src.replace(anchor, macro + anchor, 1)
    case = (
        '\t\tcase EGL_PLATFORM_SURFACELESS_MESA:\n'
        '\t\t\thybris_ws = "null";\n'
        '\t\t\tbreak;\n\n'
    )
    a2 = (
        '\t\tdefault:\n'
        '\t\t\t__eglHybrisSetError(EGL_BAD_PARAMETER);\n'
        '\t\t\treturn EGL_NO_DISPLAY;'
    )
    if a2 not in src:
        print('MISS anchor2'); sys.exit(1)
    src = src.replace(a2, case + a2, 1)

if 'EGL_MESA_platform_surfaceless' not in src:
    a3 = '\treturn ws_eglQueryString(dpy, name, _eglQueryString);\n}'
    add = (
        '\tif (dpy == EGL_NO_DISPLAY && name == EGL_EXTENSIONS && _eglQueryString) {\n'
        '\t\tconst char *real = _eglQueryString(dpy, name);\n'
        '\t\tstatic char egbuf[4096];\n'
        '\t\tsnprintf(egbuf, sizeof(egbuf) - 2, "%s %s", real ? real : "",\n'
        '\t\t\t"EGL_EXT_client_extensions EGL_EXT_platform_base EGL_MESA_platform_surfaceless");\n'
        '\t\treturn egbuf;\n'
        '\t}\n\n'
    )
    if a3 not in src:
        print('MISS anchor3'); sys.exit(1)
    src = src.replace(a3, add + a3, 1)

open(p, 'w').write(src)
print('EGL-C-PATCHED')

import re

p = '/root/ub-libhybris/hybris/egl/egl.c'
src = open(p).read()
if 'EGL_PLATFORM_SURFACELESS_MESA' in src:
    print('already patched')
else:
    macro = (
        '#ifndef EGL_PLATFORM_SURFACELESS_MESA\n'
        '#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD\n'
        '#endif\n'
        '#ifndef EGL_PLATFORM_SURFACELESS_MESA_KHR\n'
        '#define EGL_PLATFORM_SURFACELESS_MESA_KHR 0x31DD\n'
        '#endif\n\n'
    )
    anchor = 'static const char * _defaultEglPlatform()'
    src = src.replace(anchor, macro + anchor, 1)
    case_block = (
        '\t\tcase EGL_PLATFORM_SURFACELESS_MESA:\n'
        '\t\t\t// weston headless gl-renderer surfaceless platform: null ws\n'
        '\t\t\thybris_ws = "null";\n'
        '\t\t\tbreak;\n\n'
    )
    anchor2 = (
        '\t\tdefault:\n'
        '\t\t\t__eglHybrisSetError(EGL_BAD_PARAMETER);\n'
        '\t\t\treturn EGL_NO_DISPLAY;'
    )
    if anchor2 not in src:
        print('ANCHOR2 NOT FOUND')
    else:
        src = src.replace(anchor2, case_block + anchor2, 1)
        open(p, 'w').write(src)
        print('PATCHED egl.c')

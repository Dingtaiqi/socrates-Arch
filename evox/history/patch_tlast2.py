import io
P = "/build/evox/system/core/init/action.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "#include <android-base/file.h>" in s:
    print("include already present")
else:
    anchor = '#include "action.h"'
    if anchor in s:
        s = s.replace(anchor, "#include <android-base/file.h>\n" + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("added include android-base/file.h")
    else:
        print("anchor action.h not found")

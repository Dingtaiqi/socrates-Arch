import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "#include <sys/wait.h>" not in s:
    anchor = "#include <sys/types.h>" if "#include <sys/types.h>" in s else "#include <sys/stat.h>"
    if anchor in s:
        s = s.replace(anchor, anchor + "\n#include <sys/wait.h>", 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("sys/wait.h added after", anchor)
    else:
        # fallback: first include line
        i = s.find("#include")
        s = s[:i] + "#include <sys/wait.h>\n" + s[i:]
        io.open(P, "w", encoding="utf-8").write(s)
        print("sys/wait.h added at top")
else:
    print("already included")

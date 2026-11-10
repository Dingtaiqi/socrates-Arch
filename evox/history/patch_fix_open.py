import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''                    if (fd < 0) {
                        fd = open(dsu_file("appproc_dsu.log"),
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    }'''
new = '''                    if (fd < 0) {
                        fd = open(dsu_file("appproc_dsu.log").c_str(),
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    }'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("fixed c_str()")
else:
    print("not found / already fixed")

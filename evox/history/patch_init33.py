import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 1) kmsg dump 改用 raw write
old = '''                if (!out.empty()) {
                    android::base::WriteStringToFile(out, "/metadata/gsi/dsu/kmsg.log");
                }'''
new = '''                if (!out.empty()) {
                    int ofd = open("/metadata/gsi/dsu/kmsg.log",
                                   O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
                    if (ofd >= 0) {
                        (void)write(ofd, out.data(), out.size());
                        close(ofd);
                    }
                }'''
if old in s:
    s = s.replace(old, new, 1)
    print("kmsg dump -> raw write")
elif "O_TRUNC | O_CLOEXEC, 0666" in s:
    print("raw write already")
else:
    print("kmsg dump pattern NOT FOUND")

# 2) watchdog -> 180s
if "        for (int i = 0; i < 90; ++i) {" in s:
    s = s.replace("        for (int i = 0; i < 90; ++i) {", "        for (int i = 0; i < 180; ++i) {", 1)
    s = s.replace("boot not completed in 90s", "boot not completed in 180s")
    print("watchdog 180s")
elif "        for (int i = 0; i < 180; ++i) {" in s:
    print("watchdog already 180")

io.open(P, "w", encoding="utf-8").write(s)

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "        for (int i = 0; i < 90; ++i) {" in s:
    s = s.replace("        for (int i = 0; i < 90; ++i) {", "        for (int i = 0; i < 30; ++i) {", 1)
    s = s.replace("boot not completed in 90s", "boot not completed in 30s")
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog 30s")
else:
    print("anchor 90 not found")

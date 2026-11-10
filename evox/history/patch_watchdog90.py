import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = "        for (int i = 0; i < 600; ++i) {"
new = "        for (int i = 0; i < 90; ++i) {"
if old in s:
    s = s.replace(old, new, 1)
    s = s.replace("boot not completed in 600s", "boot not completed in 90s")
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog set to 90s")
else:
    print("NOT FOUND")
    idx = s.find("dsu_boot_watchdog")
    print(s[idx:idx+300])

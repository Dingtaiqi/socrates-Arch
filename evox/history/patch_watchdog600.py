import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = "        for (int i = 0; i < 20; ++i) {"
new = "        for (int i = 0; i < 600; ++i) {"
if old in s:
    s = s.replace(old, new, 1)
    s = s.replace("boot not completed in 20s", "boot not completed in 600s")
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog set to 600s")
else:
    print("anchor not found; current watchdog code:")
    idx = s.find("dsu_boot_watchdog")
    print(s[max(0,idx-200):idx+400])

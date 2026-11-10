import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''            if (tick == 250) {
                android::base::WriteStringToFile("reboot_at_250", "/metadata/gsi/dsu/auto_reboot");
                android::base::SetProperty("sys.powerctl", "reboot");
                return;
            }'''
new = '''            if (tick == 250) {
                android::base::WriteStringToFile("reboot_at_250", "/metadata/gsi/dsu/auto_reboot");
                android::base::SetProperty("sys.powerctl", "reboot");
                _exit(0);
            }'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("fixed return -> _exit(0)")
else:
    print("anchor not found or already fixed")

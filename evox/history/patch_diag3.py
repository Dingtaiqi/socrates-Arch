import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) dsu_file: 每次都尝试 mkdir，确保 persist 挂载后能用
old = '''        auto dsu_file = [](const std::string& name) -> std::string {
            if (access("/mnt/vendor/persist/dsu", W_OK) == 0) {
                return "/mnt/vendor/persist/dsu/" + name;
            }
            return "/metadata/gsi/dsu/" + name;
        };'''
new = '''        auto dsu_file = [](const std::string& name) -> std::string {
            if (access("/mnt/vendor/persist", F_OK) == 0) {
                mkdir("/mnt/vendor/persist/dsu", 0777);
                if (access("/mnt/vendor/persist/dsu", W_OK) == 0) {
                    return "/mnt/vendor/persist/dsu/" + name;
                }
            }
            return "/metadata/gsi/dsu/" + name;
        };'''
if old in s:
    s = s.replace(old, new, 1)
    print("dsu_file mkdir-each-call ok")

# 2) watchdog 250 -> 600，循环上限 360 -> 900
s = s.replace('''            if (tick == 250) {
                android::base::WriteStringToFile("reboot_at_250", dsu_file("auto_reboot"));''',
              '''            if (tick == 600) {
                android::base::WriteStringToFile("reboot_at_600", dsu_file("auto_reboot"));''')
s = s.replace("for (int tick = 0; tick < 360; ++tick) {", "for (int tick = 0; tick < 900; ++tick) {")
print("watchdog set:", "tick == 600" in s, "tick < 900" in s)

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp updated")
else:
    print("NO CHANGE")

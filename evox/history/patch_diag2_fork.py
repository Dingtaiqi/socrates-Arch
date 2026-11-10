import io, re
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) 在 fork 子进程开头插入 dsu_file helper + 持久化目录
old_head = '''    pid_t dsu_diag_pid = fork();
    if (dsu_diag_pid == 0) {
        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/diag_started");'''
new_head = '''    pid_t dsu_diag_pid = fork();
    if (dsu_diag_pid == 0) {
        // [dsu_diag] 日志优先写 /mnt/vendor/persist/dsu（/metadata 在某些阶段会写失败）
        mkdir("/mnt/vendor/persist/dsu", 0777);
        auto dsu_file = [](const std::string& name) -> std::string {
            if (access("/mnt/vendor/persist/dsu", W_OK) == 0) {
                return "/mnt/vendor/persist/dsu/" + name;
            }
            return "/metadata/gsi/dsu/" + name;
        };
        android::base::WriteStringToFile("1", dsu_file("diag_started"));'''
if old_head in s:
    s = s.replace(old_head, new_head, 1)
    print("head ok")

# 2) 扩宽 watchdog 到 600s
s = s.replace('''            if (tick == 250) {
                android::base::WriteStringToFile("reboot_at_250", dsu_file("auto_reboot"));''',
              '''            if (tick == 600) {
                android::base::WriteStringToFile("reboot_at_600", dsu_file("auto_reboot"));''')

# 3) 仅处理 fork 子进程区域：把 "/metadata/gsi/dsu/xxx" 字面量替换成 dsu_file("xxx")
start = s.find('pid_t dsu_diag_pid = fork();')
end = s.find('        _exit(0);\n    }', start)
if start > 0 and end > start:
    region = s[start:end]
    # 只替换字符串字面量形式
    region2 = re.sub(r'"/metadata/gsi/dsu/([A-Za-z0-9_\.]+)"', r'dsu_file("\1")', region)
    # 拼接形式: "/metadata/gsi/dsu/dmesg_" + std::to_string(tick) + ".log"
    region2 = region2.replace('"/metadata/gsi/dsu/dmesg_" + std::to_string(tick) + ".log"',
                              'dsu_file("dmesg_" + std::to_string(tick) + ".log")')
    region2 = region2.replace('"/metadata/gsi/dsu/mounts_" + tag + ".txt"',
                              'dsu_file("mounts_" + tag + ".txt")')
    region2 = region2.replace('"/metadata/gsi/dsu/props_" + tag + ".txt"',
                              'dsu_file("props_" + tag + ".txt")')
    region2 = region2.replace('("/metadata/gsi/dsu/kmsg_" + tag + ".log").c_str()',
                              'dsu_file("kmsg_" + tag + ".log").c_str()')
    s = s[:start] + region2 + s[end:]
    print("region literals replaced:", region.count('/metadata/gsi/dsu/'), "->", region2.count('/metadata/gsi/dsu/'))
else:
    print("region NOT found")

# 4) 增加 logcat 抓取（在 kmsg dump 分支前）
old_logcat_anchor = '''            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {'''
new_logcat_anchor = '''            if (tick == 15 || tick == 30 || tick == 60 || tick == 120 || tick == 180 || tick == 300) {
                std::string tag = std::to_string(tick);
                pid_t lp = fork();
                if (lp == 0) {
                    std::string dst = dsu_file("logcat_" + tag + ".log");
                    int fd = open(dst.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
                    if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
                    execl("/system/bin/logcat", "logcat", "-b", "all", "-d", "-v", "threadtime", nullptr);
                    _exit(127);
                }
            }
            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 40 || tick == 60 || tick == 120 || tick == 180 || tick == 240 || tick == 300 || tick == 420 || tick == 540) {'''
if old_logcat_anchor in s:
    s = s.replace(old_logcat_anchor, new_logcat_anchor, 1)
    print("logcat dump added")
else:
    print("logcat anchor NOT found")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp updated")
else:
    print("NO CHANGE")

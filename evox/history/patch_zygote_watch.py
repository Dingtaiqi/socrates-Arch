import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
i = s.find("dsu_boot_watchdog")
j = s.find("}).detach();", i)
if i < 0 or j < 0:
    print("watchdog block not found")
else:
    # 从 "// [dsu_boot_watchdog]" 注释开始到 detach 结束
    start = s.rfind("    // [dsu_boot_watchdog]", 0, i)
    end = j + len("}).detach();")
    new_block = '''    // [dsu_zygote_watch] DSU debug: panic as soon as zygote dies, so minidump
    // captures the few seconds around the crash.
    std::thread([] {
        bool seen_start = false;
        for (int i = 0; i < 600; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            auto st = android::base::GetProperty("init.svc.zygote", "");
            if (st == "running" || st == "starting") {
                seen_start = true;
            } else if (seen_start && (st == "stopped" || st == "restarting")) {
                LOG(ERROR) << "[dsu_zygote_watch] zygote state=" << st << ", panic to capture log";
                int fd = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
                if (fd >= 0) { (void)write(fd, "c", 1); close(fd); }
                return;
            } else if (!seen_start && i > 240) {  // 120s 还没启动
                LOG(ERROR) << "[dsu_zygote_watch] zygote never started, state=" << st;
                int fd = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
                if (fd >= 0) { (void)write(fd, "c", 1); close(fd); }
                return;
            }
        }
    }).detach();'''
    s = s[:start] + new_block + s[end:]
    io.open(P, "w", encoding="utf-8").write(s)
    print("zygote watch installed")

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

start_marker = "    // [dsu_zygote_watch]"
start = s.find(start_marker)
if start < 0:
    raise SystemExit("zygote watch block not found")
end_marker = "    }).detach();"
end = s.find(end_marker, start)
end += len(end_marker)

new_block = '''    // [dsu_zygote_watch] 崩溃即 panic，minidump 捕获 app_process stderr
    std::thread([] {
        std::string last_state;
        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            auto st = android::base::GetProperty("init.svc.zygote", "");
            if (st != last_state) {
                LOG(ERROR) << "[dsu_zygote_watch] zygote state: " << last_state << " -> " << st
                           << " at tick " << i;
                last_state = st;
                if (st == "restarting" || st == "stopped") {
                    android::base::WriteStringToFile(st, "/metadata/gsi/dsu/zygote_last_state");
                    dsu_check_paths("zygote_fail_" + std::to_string(i));
                    LOG(ERROR) << "[dsu_zygote_watch] panicking to capture app_process stderr";
                    int fd = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
                    if (fd >= 0) { (void)write(fd, "c", 1); close(fd); }
                    return;
                }
            }
        }
    }).detach();'''

s = s[:start] + new_block + s[end:]
io.open(P, "w", encoding="utf-8").write(s)
print("zygote watch -> panic on restart; size:", len(s))

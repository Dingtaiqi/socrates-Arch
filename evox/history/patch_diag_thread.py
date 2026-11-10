import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 找到两个线程块的起止并整体替换
start_marker = "    // [dsu_kmsg_dump] DSU debug: periodically dump full kernel log to /metadata"
end_marker = "    // Copy logs captures from pstore. Flush the logs when boot completes"
i = s.find(start_marker)
j = s.find(end_marker)
if i < 0 or j < 0 or j < i:
    print("markers not found", i, j)
    raise SystemExit(1)

new_block = '''    // [dsu_diag] 单线程诊断：定时记录属性/挂载/内核日志，不 panic
    std::thread([] {
        for (int tick = 0; tick < 360; ++tick) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                android::base::WriteStringToFile("1", "/metadata/gsi/dsu/boot_completed_seen");
                break;
            }
            if (tick % 5 == 0) {
                std::string s = std::to_string(tick) + " boot=" +
                    android::base::GetProperty("sys.boot_completed", "?") +
                    " zygote=" + android::base::GetProperty("init.svc.zygote", "?") +
                    " vold=" + android::base::GetProperty("init.svc.vold", "?") +
                    " apexd=" + android::base::GetProperty("apexd.status", "?") +
                    " crypto=" + android::base::GetProperty("ro.crypto.state", "?") +
                    " user0=" + android::base::GetProperty("sys.user.0.ce_available", "?");
                android::base::WriteStringToFile(s, "/metadata/gsi/dsu/beat");
            }
            if (tick == 20 || tick == 60 || tick == 120 || tick == 240) {
                std::string tag = std::to_string(tick);
                // 挂载表
                std::string mounts;
                if (android::base::ReadFileToString("/proc/mounts", &mounts)) {
                    android::base::WriteStringToFile(mounts,
                        "/metadata/gsi/dsu/mounts_" + tag + ".txt");
                }
                // 属性快照
                std::string props;
                for (const char* p : {"init.svc.zygote", "init.svc.vold", "init.svc.apexd",
                                      "init.svc.servicemanager", "init.svc.netd",
                                      "init.svc.keystore2", "init.svc.surfaceflinger",
                                      "apexd.status", "sys.boot_completed", "ro.crypto.state",
                                      "vold.decrypt", "vold.post_fs_data_done"}) {
                    props += std::string(p) + "=" + android::base::GetProperty(p, "?") + "\\n";
                }
                android::base::WriteStringToFile(props, "/metadata/gsi/dsu/props_" + tag + ".txt");
                // 内核日志: /dev/kmsg 原始读取
                int kfd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
                if (kfd >= 0) {
                    std::string out;
                    char lbuf[16384];
                    for (int k = 0; k < 4000; ++k) {
                        ssize_t r = read(kfd, lbuf, sizeof(lbuf));
                        if (r <= 0) break;
                        out.append(lbuf, r);
                    }
                    close(kfd);
                    if (!out.empty()) {
                        int ofd = open(("/metadata/gsi/dsu/kmsg_" + tag + ".log").c_str(),
                                       O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
                        if (ofd >= 0) {
                            (void)write(ofd, out.data(), out.size());
                            close(ofd);
                        }
                    }
                }
            }
        }
    }).detach();

'''
s = s[:i] + new_block + s[j:]
io.open(P, "w", encoding="utf-8").write(s)
print("replaced ok, new size:", len(s))

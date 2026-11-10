import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

anchor = '''            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 40 || tick == 60 || tick == 120 || tick == 180 || tick == 240 || tick == 300 || tick == 420 || tick == 540) {'''
if "dsu_psdump" in s:
    print("already present")
elif anchor in s:
    block = '''            // [dsu_psdump] 进程表快照 + logcat 抓取（定位 system_server 是否启动/崩溃）
            if (tick <= 30 || tick == 45 || tick == 60 || tick == 90 || tick == 120) {
                std::string plist;
                DIR* pd = opendir("/proc");
                bool has_ss = false;
                if (pd) {
                    struct dirent* de5;
                    while ((de5 = readdir(pd)) != nullptr) {
                        if (de5->d_name[0] < '0' || de5->d_name[0] > '9') continue;
                        std::string cl;
                        if (!android::base::ReadFileToString(std::string("/proc/") + de5->d_name + "/cmdline", &cl)) continue;
                        for (auto& c : cl) if (c == '\\0') c = ' ';
                        plist += std::string(de5->d_name) + " " + cl + "\\n";
                        if (cl.find("system_server") != std::string::npos) has_ss = true;
                    }
                    closedir(pd);
                }
                android::base::WriteStringToFile(plist, dsu_file("ps_" + std::to_string(tick) + ".txt"));
                if (has_ss) android::base::WriteStringToFile("1", dsu_file("has_system_server"));
            }
            if (tick == 10 || tick == 15 || tick == 20 || tick == 30 || tick == 45 || tick == 60 || tick == 90 || tick == 120) {
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
'''
    s = s.replace(anchor, block + anchor, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("psdump/logcat block inserted")
else:
    print("anchor NOT found")

if s != orig:
    print("changed")

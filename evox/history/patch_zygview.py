import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

if "dsu_zygview" in s:
    print("already")
else:
    anchor = '''            // [dsu_psdump] 进程表快照 + logcat 抓取（定位 system_server 是否启动/崩溃）'''
    block = '''            // [dsu_zygview] 对照 init/zygote/system_server 三个视角的 /dev/socket 可见性
            if (tick == 15 || tick == 20 || tick == 25 || tick == 30 || tick == 45 || tick == 60) {
                std::string tag = std::to_string(tick);
                // /proc/net/unix：看 zygote socket 是否真的存在于网络命名空间
                std::string unixs;
                android::base::ReadFileToString("/proc/net/unix", &unixs);
                android::base::WriteStringToFile(unixs, dsu_file("unix_" + tag + ".txt"));
                // 扫描 zygote 相关进程：cmdline 含 zygote
                std::string views;
                DIR* pd = opendir("/proc");
                if (pd) {
                    struct dirent* de6;
                    while ((de6 = readdir(pd)) != nullptr) {
                        if (de6->d_name[0] < '0' || de6->d_name[0] > '9') continue;
                        std::string base = std::string("/proc/") + de6->d_name;
                        std::string cl;
                        if (!android::base::ReadFileToString(base + "/cmdline", &cl)) continue;
                        // cmdline 以 NUL 分隔
                        std::string first = cl.substr(0, cl.find('\\0'));
                        if (first.find("zygote") == std::string::npos) continue;
                        views += "=== pid " + std::string(de6->d_name) + " cmdline=" + first + "\\n";
                        std::string stt;
                        android::base::ReadFileToString(base + "/status", &stt);
                        // 取 Name/Uid/PPid 行
                        for (const char* key : {"Name:", "Uid:", "PPid:", "Seccomp:"}) {
                            size_t p = stt.find(key);
                            if (p != std::string::npos) {
                                size_t e = stt.find('\\n', p);
                                views += "  " + stt.substr(p, e - p) + "\\n";
                            }
                        }
                        struct stat zs;
                        std::string zpath = base + "/root/dev/socket/zygote";
                        if (stat(zpath.c_str(), &zs) == 0) {
                            views += "  /dev/socket/zygote VISIBLE ino=" + std::to_string(zs.st_ino) + "\\n";
                        } else {
                            views += "  /dev/socket/zygote MISSING errno=" + std::to_string(errno) + "\\n";
                        }
                        std::string mi;
                        android::base::ReadFileToString(base + "/mountinfo", &mi);
                        // 只保留 /dev 相关行
                        std::istringstream iss(mi);
                        std::string line;
                        while (std::getline(iss, line)) {
                            if (line.find(" /dev ") != std::string::npos ||
                                line.find(" /dev/socket ") != std::string::npos) {
                                views += "  MI: " + line + "\\n";
                            }
                        }
                    }
                    closedir(pd);
                }
                android::base::WriteStringToFile(views, dsu_file("zygviews_" + tag + ".txt"));
            }
'''
    if anchor in s:
        s = s.replace(anchor, block + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("zygview inserted")
    else:
        print("anchor NOT found")

# 需要 <sstream>
if "#include <sstream>" not in s:
    s = s.replace("#include <string>", "#include <sstream>\n#include <string>", 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("sstream include ensured")

if s != orig:
    print("changed")

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

if "dsu_sockstat" in s:
    print("already patched")
else:
    anchor = '''            if (tick % 1 == 0) {'''
    ins = '''            {
                // [dsu_sockstat] 每 tick 记录 /dev/socket/zygote 状态 + system_server 的命名空间
                struct stat zsb;
                std::string z;
                if (stat("/dev/socket/zygote", &zsb) == 0) {
                    z = "ok ino=" + std::to_string(zsb.st_ino);
                } else {
                    z = "MISSING errno=" + std::to_string(errno);
                }
                android::base::WriteStringToFile(z, dsu_file("sockstat"));
                if (tick == 20 || tick == 30 || tick == 45 || tick == 60) {
                    // 扫描 system_server 进程，记录它的 root 视角
                    DIR* pd = opendir("/proc");
                    if (pd) {
                        struct dirent* de3;
                        while ((de3 = readdir(pd)) != nullptr) {
                            if (de3->d_name[0] < '0' || de3->d_name[0] > '9') continue;
                            std::string cl;
                            std::string cp = std::string("/proc/") + de3->d_name + "/cmdline";
                            if (!android::base::ReadFileToString(cp, &cl)) continue;
                            if (cl.find("system_server") == std::string::npos) continue;
                            std::string root = std::string("/proc/") + de3->d_name + "/root";
                            std::string lst;
                            DIR* sd = opendir((root + "/dev/socket").c_str());
                            if (sd) {
                                struct dirent* de4;
                                while ((de4 = readdir(sd)) != nullptr) {
                                    if (de4->d_name[0] == '.') continue;
                                    lst += de4->d_name; lst += "\\n";
                                }
                                closedir(sd);
                            } else {
                                lst = "OPEN_FAIL errno=" + std::to_string(errno);
                            }
                            std::string tag = std::to_string(tick) + "_" + de3->d_name;
                            android::base::WriteStringToFile(lst, dsu_file("sssockets_" + tag + ".txt"));
                            std::string mi;
                            android::base::ReadFileToString(std::string("/proc/") + de3->d_name + "/mountinfo", &mi);
                            android::base::WriteStringToFile(mi, dsu_file("ssmountinfo_" + tag + ".txt"));
                            break;
                        }
                        closedir(pd);
                    }
                }
            }
'''
    if anchor in s:
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("sockstat inserted")
    else:
        print("anchor NOT found")

if s != orig:
    print("changed")

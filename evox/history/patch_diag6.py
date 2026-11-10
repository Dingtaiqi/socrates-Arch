import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

if "dsu_socket_dump" in s:
    print("already added")
else:
    anchor = '''            if (tick == 20 || tick == 60 || tick == 120 || tick == 180 || tick == 240 || tick == 300 || tick == 420) {'''
    ins = '''            if (tick == 25 || tick == 45 || tick == 65 || tick == 90 || tick == 120) {
                // [dsu_socket_dump] /dev/socket 与 /dev 清单（排查 zygote socket 连接失败）
                std::string dump;
                const char* dirs[] = {"/dev/socket", "/dev"};
                for (const char* dser : dirs) {
                    dump += std::string("### ") + dser + "\\n";
                    DIR* dx = opendir(dser);
                    if (!dx) { dump += "OPEN_FAIL\\n"; continue; }
                    struct dirent* de2;
                    while ((de2 = readdir(dx)) != nullptr) {
                        if (de2->d_name[0] == '.') continue;
                        dump += de2->d_name;
                        dump += "\\n";
                    }
                    closedir(dx);
                }
                android::base::WriteStringToFile(dump, dsu_file("devdump_" + std::to_string(tick) + ".txt"));
                // 同时记录 zygote 进程 cmdline/state/mountinfo 是否可见
                std::string zin;
                android::base::ReadFileToString("/proc/1/mountinfo", &zin);
                android::base::WriteStringToFile(zin, dsu_file("init_mountinfo_" + std::to_string(tick) + ".txt"));
            }
'''
    if anchor in s:
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("socket dump inserted")
    else:
        print("anchor NOT found")

if s != orig:
    print("changed")

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) diag 子进程：增加 tombstone/dropbox 复制
anchor = '''            if (tick == 15 || tick == 30 || tick == 60 || tick == 120 || tick == 180 || tick == 300) {'''
ins = '''            if (tick == 20 || tick == 60 || tick == 120 || tick == 180 || tick == 240 || tick == 300 || tick == 420) {
                // [dsu_diag] 复制 tombstone / dropbox 到 persist，供宿主读取
                const char* srcs[] = {"/data/tombstones", "/data/system/dropbox", "/data/anr"};
                for (const char* src : srcs) {
                    DIR* d = opendir(src);
                    if (!d) continue;
                    struct dirent* de;
                    int n = 0;
                    while ((de = readdir(d)) != nullptr && n < 4) {
                        if (de->d_name[0] == '.') continue;
                        std::string sp = std::string(src) + "/" + de->d_name;
                        std::string content;
                        if (!android::base::ReadFileToString(sp, &content)) continue;
                        std::string name = std::string(src);
                        for (auto& ch : name) if (ch == '/') ch = '_';
                        android::base::WriteStringToFile(
                            content, dsu_file("crash_" + std::to_string(tick) + name + "_" + de->d_name));
                        ++n;
                    }
                    closedir(d);
                }
                // logcat 带 stderr/exit code
                pid_t lp2 = fork();
                if (lp2 == 0) {
                    std::string dst = dsu_file("logcat2_" + std::to_string(tick) + ".log");
                    int fd = open(dst.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
                    if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
                    execl("/system/bin/logcat", "logcat", "-b", "all", "-d", "-v", "threadtime", nullptr);
                    _exit(127);
                }
            }
'''
if anchor in s:
    s = s.replace(anchor, ins + anchor, 1)
    print("tombstone/logcat2 diag inserted")
else:
    print("anchor NOT found")

# 2) 需要 <dirent.h>
if "#include <dirent.h>" not in s:
    s = s.replace('#include <fcntl.h>', '#include <dirent.h>\n#include <fcntl.h>', 1)
    print("dirent include added")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp updated")
else:
    print("NO CHANGE")

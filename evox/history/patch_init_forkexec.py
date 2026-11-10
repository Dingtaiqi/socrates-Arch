import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
anchor = '''            if (tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {'''
add = '''            if (tick == 16) {
                // [dsu-port] init 直接 fork+exec app_process，stderr 重定向到 /metadata
                pid_t p = fork();
                if (p == 0) {
                    int fd = open("/metadata/gsi/dsu/appproc_init.log",
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    if (fd >= 0) {
                        dup2(fd, 1);
                        dup2(fd, 2);
                    }
                    const char* argv[] = {"/system/bin/app_process64", "-Xzygote", "/system/bin",
                                          "--zygote", "--start-system-server",
                                          "--socket-name=zygote_dbg3", nullptr};
                    execv(argv[0], (char* const*)argv);
                    _exit(113);
                } else if (p > 0) {
                    LOG(ERROR) << "[du_init_zygote_exec] forked pid=" << p;
                } else {
                    LOG(ERROR) << "[du_init_zygote_exec] fork failed errno=" << errno;
                }
            }
'''
if anchor in s:
    s = s.replace(anchor, add + anchor, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("init fork+exec added")
else:
    print("anchor not found")

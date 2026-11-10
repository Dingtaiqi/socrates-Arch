import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''            if (tick == 16) {
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
new = '''            if (tick == 40) {
                // [dsu-port] init 直接 fork+exec app_process，stderr 重定向到 /metadata
                pid_t p = fork();
                if (p == 0) {
                    int fd = open("/metadata/gsi/dsu/appproc_init.log",
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    if (fd >= 0) {
                        dup2(fd, 1);
                        dup2(fd, 2);
                        const char* hello = "HELLO_FROM_INIT_CHILD\\n";
                        ssize_t hw = write(fd, hello, strlen(hello));
                        (void)hw;
                        int hfd = open("/metadata/gsi/dsu/appproc_init_marker.log",
                                       O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                        if (hfd >= 0) {
                            char mb[96];
                            int mn = snprintf(mb, sizeof(mb), "child pid=%d fd=%d hw=%zd\\n",
                                              getpid(), fd, hw);
                            if (mn > 0) { ssize_t w2 = write(hfd, mb, (size_t)mn); (void)w2; }
                            close(hfd);
                        }
                    }
                    const char* argv[] = {"/system/bin/app_process64", "-Xzygote", "/system/bin",
                                          "--zygote", "--start-system-server",
                                          "--socket-name=zygote_dbg3", nullptr};
                    execv(argv[0], (char* const*)argv);
                    int ev = errno;
                    if (fd >= 0) {
                        char eb[96];
                        int en = snprintf(eb, sizeof(eb), "EXEC_FAILED errno=%d\\n", ev);
                        if (en > 0) { ssize_t w3 = write(fd, eb, (size_t)en); (void)w3; }
                    }
                    _exit(113);
                } else if (p > 0) {
                    android::base::WriteStringToFile("forked_pid=" + std::to_string(p),
                                                     "/metadata/gsi/dsu/appproc_fork.txt");
                } else {
                    android::base::WriteStringToFile("fork_failed_errno=" + std::to_string(errno),
                                                     "/metadata/gsi/dsu/appproc_fork.txt");
                }
            }
'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("fork+exec v2 written")
else:
    print("old block NOT found")

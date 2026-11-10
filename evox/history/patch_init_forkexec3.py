import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old_start = '''            if (tick == 40) {'''
old_end = '''                    _exit(113);
                } else if (p > 0) {
                    android::base::WriteStringToFile("forked_pid=" + std::to_string(p),
                                                     "/metadata/gsi/dsu/appproc_fork.txt");
                } else {
                    android::base::WriteStringToFile("fork_failed_errno=" + std::to_string(errno),
                                                     "/metadata/gsi/dsu/appproc_fork.txt");
                }
            }
'''
i = s.find(old_start)
j = s.find(old_end)
if i < 0 or j < 0:
    print("block not found", i, j)
else:
    new_block = '''            if (tick == 40) {
                // [dsu-port] fork+exec app_process，stderr -> persist 共享分区
                pid_t p = fork();
                if (p == 0) {
                    int fd = open("/mnt/vendor/persist/appproc_dsu.log",
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    if (fd < 0) {
                        fd = open("/metadata/gsi/dsu/appproc_dsu.log",
                                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
                    }
                    if (fd >= 0) {
                        const char* hello = "HELLO_FROM_CHILD\\n";
                        ssize_t hw = write(fd, hello, strlen(hello));
                        (void)hw;
                        dup2(fd, 1);
                        dup2(fd, 2);
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
                    int st = 0;
                    waitpid(p, &st, 0);
                    std::string msg = "fork_pid=" + std::to_string(p) +
                                      " status=" + std::to_string(st) +
                                      " exited=" + std::to_string(WIFEXITED(st)) +
                                      " code=" + std::to_string(WEXITSTATUS(st)) +
                                      " signaled=" + std::to_string(WIFSIGNALED(st)) +
                                      " sig=" + std::to_string(WIFSIGNALED(st) ? WTERMSIG(st) : 0);
                    android::base::WriteStringToFile(msg, "/metadata/gsi/dsu/appproc_fork.txt");
                    android::base::WriteStringToFile(msg, "/mnt/vendor/persist/appproc_fork.txt");
                } else {
                    android::base::WriteStringToFile("fork_failed_errno=" + std::to_string(errno),
                                                     "/metadata/gsi/dsu/appproc_fork.txt");
                }
            }
'''
    s = s[:i] + new_block + s[j+len(old_end):]
    io.open(P, "w", encoding="utf-8").write(s)
    print("fork+exec v3 (persist) written")

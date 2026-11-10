import io
P = "/build/evox/system/core/init/service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "svc_exit.log" in s:
    print("already patched")
else:
    old = '''    for (const auto& f : reap_callbacks_) {
        f(siginfo);
    }
'''
    new = '''    for (const auto& f : reap_callbacks_) {
        f(siginfo);
    }

    // [dsu-port] 记录服务退出状态，便于定位 zygote/netd 崩溃
    {
        std::string line = name_ + " code=" + std::to_string(siginfo.si_code) +
                           " status=" + std::to_string(siginfo.si_status) + "\\n";
        int fd = open("/metadata/gsi/dsu/svc_exit.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
        if (fd >= 0) {
            (void)write(fd, line.data(), line.size());
            close(fd);
        }
    }
'''
    if old in s:
        s = s.replace(old, new, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("svc_exit logging inserted")
    else:
        print("anchor NOT found")

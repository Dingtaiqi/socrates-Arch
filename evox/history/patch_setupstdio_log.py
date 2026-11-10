import io
P = "/build/evox/system/core/init/service_utils.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''    dup2(out.get(), STDOUT_FILENO);
    dup2(out.get(), STDERR_FILENO);
    // [dsu-port] 标记：证明 SetupStdio 执行了
    {
        int mfd = open("/metadata/gsi/dsu/setupstdio_marker.log",
                       O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
        if (mfd >= 0) {
            char b[128];
            int n = snprintf(b, sizeof(b), "SetupStdio pid=%d\\n", getpid());
            if (n > 0) { ssize_t w = write(mfd, b, (size_t)n); (void)w; }
            close(mfd);
        }
    }
}'''
new = '''    dup2(out.get(), STDOUT_FILENO);
    dup2(out.get(), STDERR_FILENO);
    // [dsu-port] 把 fd 与 write 结果写进 kmsg（init 日志），便于定位
    {
        int mfd = open("/metadata/gsi/dsu/setupstdio_marker.log",
                       O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
        ssize_t w = -1;
        int e = 0;
        if (mfd >= 0) {
            char b[160];
            int n = snprintf(b, sizeof(b), "SetupStdio pid=%d\\n", getpid());
            if (n > 0) { w = write(mfd, b, (size_t)n); e = errno; }
            close(mfd);
        } else {
            e = errno;
        }
        LOG(ERROR) << "[du_setupstdio] outfd=" << out.get() << " markfd=" << mfd
                   << " write=" << w << " errno=" << e;
    }
}'''
if old in s:
    s = s.replace(old, new, 1)
    print("patched with kmsg logging")
else:
    print("old marker block NOT found")

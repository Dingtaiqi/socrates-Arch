import io
P = "/build/evox/system/core/init/service_utils.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
anchor = '''    dup2(out.get(), STDOUT_FILENO);
    dup2(out.get(), STDERR_FILENO);
}'''
new = '''    dup2(out.get(), STDOUT_FILENO);
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
if anchor in s:
    s = s.replace(anchor, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("marker added")
else:
    print("anchor not found")

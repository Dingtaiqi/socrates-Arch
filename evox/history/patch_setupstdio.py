import io
P = "/build/evox/system/core/init/service_utils.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''void SetupStdio(bool stdio_to_kmsg) {
    auto fd = unique_fd{open("/dev/null", O_RDWR | O_CLOEXEC)};
    dup2(fd.get(), STDIN_FILENO);
    if (stdio_to_kmsg) {
        fd.reset(open("/dev/kmsg_debug", O_WRONLY | O_CLOEXEC));
        if (fd == -1) fd.reset(open("/dev/null", O_WRONLY | O_CLOEXEC));
    }
    dup2(fd.get(), STDOUT_FILENO);
    dup2(fd.get(), STDERR_FILENO);
}'''
new = '''void SetupStdio(bool stdio_to_kmsg) {
    auto fd = unique_fd{open("/dev/null", O_RDWR | O_CLOEXEC)};
    dup2(fd.get(), STDIN_FILENO);
    unique_fd out;
    if (stdio_to_kmsg) {
        out.reset(open("/dev/kmsg_debug", O_WRONLY | O_CLOEXEC));
        if (out == -1) out.reset(open("/dev/null", O_WRONLY | O_CLOEXEC));
    } else {
        // [dsu-port] 服务 stdout/stderr 落到 /metadata，供 DSU 调试捕获
        out.reset(open("/metadata/gsi/dsu/svc_stdio.log",
                       O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666));
        if (out == -1) out.reset(open("/dev/null", O_WRONLY | O_CLOEXEC));
    }
    dup2(out.get(), STDOUT_FILENO);
    dup2(out.get(), STDERR_FILENO);
}'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched SetupStdio")
else:
    print("pattern NOT found")

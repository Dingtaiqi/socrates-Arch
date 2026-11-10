import io
P = "/build/evox/system/core/init/service_utils.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

old = '''        // [dsu-port] 服务 stdout/stderr 落到 /metadata，供 DSU 调试捕获
        out.reset(open("/metadata/gsi/dsu/svc_stdio.log",
                       O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666));
        if (out == -1) out.reset(open("/dev/null", O_WRONLY | O_CLOEXEC));'''
new = '''        // [dsu-port] 恢复标准行为：非 stdio_to_kmsg 服务 stdout/stderr 到 /dev/null。
        // 注意：绝不能重定向到真实文件——dup2 会清掉 CLOEXEC，system_server 继承后会因
        // "Not allowlisted (80): <file>" 的 JNI fd 检查直接 abort。
        out.reset(open("/dev/null", O_WRONLY | O_CLOEXEC));'''
if old in s:
    s = s.replace(old, new, 1)
    print("svc_stdio redirect removed")
else:
    print("anchor1 NOT found")

# 移除 setupstdio_marker 块
old2 = '''    // [dsu-port] 标记：证明 SetupStdio 执行了
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
'''
if old2 in s:
    s = s.replace(old2, "", 1)
    print("setupstdio marker removed")
else:
    print("anchor2 NOT found (maybe already removed)")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("service_utils.cpp updated")
else:
    print("NO CHANGE")

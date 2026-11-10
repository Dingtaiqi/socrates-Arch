import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) kmsg dump 改用 klogctl（避免 /dev/kmsg read 审计刷屏淹没 zygote 输出）
old = '''                // 内核日志: /dev/kmsg 原始读取
                int kfd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
                if (kfd >= 0) {
                    std::string out;
                    char lbuf[16384];
                    for (int k = 0; k < 4000; ++k) {
                        ssize_t r = read(kfd, lbuf, sizeof(lbuf));
                        if (r <= 0) break;
                        out.append(lbuf, r);
                    }
                    close(kfd);
                    if (!out.empty()) {'''
new = '''                // 内核日志: klogctl 读取（不产生 AVC 审计刷屏）
                {
                    std::string out;
                    for (int ksz = 1 << 20; ksz >= 4096; ksz >>= 1) {
                        std::vector<char> buf(ksz);
                        int n = klogctl(3, buf.data(), buf.size());
                        if (n > 0) { out.assign(buf.data(), n); break; }
                    }
                    if (!out.empty()) {'''
if old in s:
    s = s.replace(old, new, 1)
    print("klogctl dump patched")
else:
    print("kmsg dump anchor not found")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp updated")

# 2) svc_exit 写到 persist（共享分区）
P2 = "/build/evox/system/core/init/service.cpp"
s2 = io.open(P2, encoding="utf-8", errors="replace").read()
old2 = '''        int fd = open("/metadata/gsi/dsu/svc_exit.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);'''
new2 = '''        mkdir("/mnt/vendor/persist/dsu", 0777);
        int fd = open("/mnt/vendor/persist/dsu/svc_exit.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);'''
if old2 in s2:
    s2 = s2.replace(old2, new2, 1)
    io.open(P2, "w", encoding="utf-8").write(s2)
    print("svc_exit -> persist")
else:
    print("svc_exit anchor not found")

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) permissive 写失败要记录 errno，并尝试第二种写法
old1 = '''        int pfd = open("/sys/fs/selinux/enforce", O_WRONLY | O_CLOEXEC);
        int wret = -1;
        if (pfd >= 0) { wret = (int)write(pfd, "0", 1); close(pfd); }'''
new1 = '''        int pfd = open("/sys/fs/selinux/enforce", O_WRONLY | O_CLOEXEC);
        int wret = -1;
        int werr = 0;
        if (pfd >= 0) { wret = (int)write(pfd, "0", 1); werr = errno; close(pfd); }'''
s = s.replace(old1, new1, 1)
s = s.replace('std::string pr = "write_ret=" + std::to_string(wret) + " enforce_now=" + rb;',
              'std::string pr = "write_ret=" + std::to_string(wret) + " werr=" + std::to_string(werr) + " enforce_now=" + rb;', 1)

# 2) 诊断线程：每个 tick 都写 beat，tick1 dump mounts 不依赖 kmsg；kmsg 改用 klogctl
s = s.replace('''            if (tick % 5 == 0) {''', '''            if (tick % 1 == 0) {''', 1)

# 在 tick==1 的 dump 分支之前插入 klogctl 抓 dmesg
old2 = '''            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {'''
new2 = '''            if (tick == 1 || tick == 2 || tick == 3) {
                // 用 klogctl 抓内核日志（不依赖 /dev/kmsg 权限）
                std::string out;
                for (int ksz = 1 << 20; ksz >= 4096; ksz >>= 1) {
                    std::vector<char> buf(ksz);
                    int n = klogctl(3, buf.data(), buf.size());  // SYSLOG_ACTION_READ_ALL
                    if (n > 0) {
                        out.assign(buf.data(), n);
                        break;
                    }
                }
                android::base::WriteStringToFile(
                    out.empty() ? "EMPTY_OR_FAIL" : out,
                    "/metadata/gsi/dsu/dmesg_" + std::to_string(tick) + ".log");
            }
            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {'''
if old2 in s:
    s = s.replace(old2, new2, 1)

if "#include <sys/klog.h>" not in s:
    s = s.replace('#include <sys/syscall.h>', '#include <sys/syscall.h>\n#include <sys/klog.h>', 1)
    if "#include <sys/klog.h>" not in s:
        s = s.replace('#include <sys/types.h>', '#include <sys/types.h>\n#include <sys/klog.h>', 1)

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched diag/klogctl/errno")
else:
    print("no change")

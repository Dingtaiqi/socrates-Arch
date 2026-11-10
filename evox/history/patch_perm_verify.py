import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) 在 "init second stage started!" 之后插入 permissive 写入+回读+落盘
anchor1 = '    LOG(INFO) << "init second stage started!";'
ins1 = '''    LOG(INFO) << "init second stage started!";
    // [dsu-port] 进入第二阶段立刻切 permissive，并回读确认（防止策略差异导致服务被 SELinux 卡死）
    {
        int pfd = open("/sys/fs/selinux/enforce", O_WRONLY | O_CLOEXEC);
        int wret = -1;
        if (pfd >= 0) { wret = (int)write(pfd, "0", 1); close(pfd); }
        int rfd = open("/sys/fs/selinux/enforce", O_RDONLY | O_CLOEXEC);
        char rb[8] = {0};
        if (rfd >= 0) { (void)read(rfd, rb, 7); close(rfd); }
        std::string pr = "write_ret=" + std::to_string(wret) + " enforce_now=" + rb;
        android::base::WriteStringToFile(pr, "/metadata/gsi/dsu/perm.txt");
        LOG(ERROR) << "[dsu-port] permissive attempt: " << pr;
    }
'''
if anchor1 in s and "[dsu-port] permissive attempt" not in s:
    s = s.replace(anchor1, ins1, 1)
    print("permissive block inserted")

# 2) 诊断线程开头写 diag_started，且 tick 1 就 dump kmsg
s = s.replace('''    std::thread([] {
        for (int tick = 0; tick < 360; ++tick) {''',
'''    std::thread([] {
        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/diag_started");
        for (int tick = 0; tick < 360; ++tick) {''', 1)

s = s.replace('''            if (tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {''',
'''            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {''', 1)

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("diag thread patched")
else:
    print("no change")

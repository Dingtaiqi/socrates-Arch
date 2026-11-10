import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''        std::string last_state;
        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            auto st = android::base::GetProperty("init.svc.zygote", "");'''
new = '''        std::string last_state;
        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            if (i == 10) {
                int pr = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
                LOG(ERROR) << "[dsu-port] delayed permissive result=" << pr;
            }
            auto st = android::base::GetProperty("init.svc.zygote", "");'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("delayed permissive inserted into watch thread")
else:
    print("pattern not found")

import io, re
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

old_block = """        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (android::base::GetProperty("sys.boot_completed", "") == "1") return;
        }
        if (android::base::GetProperty("sys.boot_completed", "") != "1") {
            LOG(ERROR) << "[dsu_boot_watchdog] boot not completed in 1200s, triggering kernel panic";"""
new_block = """        for (int i = 0; i < 240; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        {
            LOG(ERROR) << "[dsu_boot_watchdog] 240s dump panic, boot_completed="
                       << android::base::GetProperty("sys.boot_completed", "");"""
if old_block in s:
    s = s.replace(old_block, new_block, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog -> unconditional 240s panic")
else:
    print("block not found; current:")
    i = s.find("dsu_boot_watchdog")
    print(s[i-50:i+700])

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = """        for (int i = 0; i < 30; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));"""
new = """        for (int i = 0; i < 180; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));"""
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog loop 180s done")
else:
    print("watchdog loop pattern not found")
    # 打印相关区域
    i = s.find("dsu_boot_watchdog")
    print(s[i-100:i+400])

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = """        for (int i = 0; i < 180; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));"""
new = """        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));"""
if old in s:
    s = s.replace(old, new, 1)
    s = s.replace("boot not completed in 180s", "boot not completed in 1200s")
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog 1200s")
else:
    print("pattern not found")

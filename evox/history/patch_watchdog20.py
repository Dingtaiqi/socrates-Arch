import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''    std::thread([] {
        for (int i = 0; i < 180; ++i) {'''
new = '''    std::thread([] {
        for (int i = 0; i < 20; ++i) {'''
if old in s:
    s = s.replace(old, new, 1)
    s = s.replace('boot not completed in 180s', 'boot not completed in 20s')
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog set to 20s")
else:
    print("anchor not found")

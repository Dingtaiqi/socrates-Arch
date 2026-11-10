import io

# 1) t_last 扩展到所有 trigger（去掉 early-init 过滤）
P1 = "/build/evox/system/core/init/action.cpp"
s = io.open(P1, encoding="utf-8", errors="replace").read()
old_filter = '        if (trigger_name2.find("early-init") != std::string::npos) {'
new_filter = '        if (true) {  // [dsu-port] trace all triggers'
if old_filter in s:
    s = s.replace(old_filter, new_filter, 1)
    io.open(P1, "w", encoding="utf-8").write(s)
    print("action.cpp: t_last filter removed (all triggers)")
else:
    print("action.cpp: filter anchor not found (already?)")

# 2) init 看门狗：15 秒未 boot 完成 → sysrq crash（pstore 保存 console）
P2 = "/build/evox/system/core/init/init.cpp"
s2 = io.open(P2, encoding="utf-8", errors="replace").read()
anchor = '    am.QueueEventTrigger("init");'
if "dsu_boot_watchdog" in s2:
    print("init.cpp: watchdog already present")
elif anchor in s2:
    wd = '''    am.QueueEventTrigger("init");

    // [dsu_boot_watchdog] DSU debug: panic if boot doesn't complete in 15s,
    // so ramoops/pstore captures the full console log of the hang.
    std::thread([] {
        for (int i = 0; i < 15; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            if (android::base::GetProperty("sys.boot_completed", "") == "1") return;
        }
        if (android::base::GetProperty("sys.boot_completed", "") != "1") {
            LOG(ERROR) << "[dsu_boot_watchdog] boot not completed in 15s, triggering kernel panic";
            int fd = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
            if (fd >= 0) {
                (void)write(fd, "c", 1);
                close(fd);
            }
        }
    }).detach();
'''
    s2 = s2.replace(anchor, wd, 1)
    # includes
    if "#include <thread>" not in s2:
        s2 = s2.replace("#include <sys/types.h>", "#include <sys/types.h>\n#include <thread>", 1)
    if "#include <chrono>" not in s2:
        s2 = s2.replace("#include <thread>", "#include <chrono>\n#include <thread>", 1)
    if "#include <android-base/properties.h>" not in s2:
        s2 = s2.replace("#include <android-base/logging.h>", "#include <android-base/logging.h>\n#include <android-base/properties.h>", 1)
    io.open(P2, "w", encoding="utf-8").write(s2)
    print("init.cpp: watchdog inserted")
else:
    print("init.cpp: anchor not found")

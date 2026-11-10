import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

if "dsu_kmsg_dump" in s:
    print("kmsg dump already present")
else:
    anchor = "    // [dsu_boot_watchdog] DSU debug:"
    if anchor not in s:
        print("watchdog anchor missing")
    else:
        newblk = '''    // [dsu_kmsg_dump] DSU debug: periodically dump full kernel log to /metadata
    std::thread([] {
        for (int i = 0; i < 200; ++i) {
            std::this_thread::sleep_for(std::chrono::seconds(5));
            if (android::base::GetProperty("sys.boot_completed", "") == "1") return;
            char* buf = static_cast<char*>(malloc(2 * 1024 * 1024));
            if (!buf) return;
            int n = klogctl(3 /* SYSLOG_ACTION_READ_ALL */, buf, 2 * 1024 * 1024);
            if (n > 0) {
                android::base::WriteStringToFile(std::string(buf, n),
                                                 "/metadata/gsi/dsu/kmsg.log");
            }
            free(buf);
        }
    }).detach();

'''
        s = s.replace(anchor, newblk + anchor, 1)
        # includes
        for inc, anch in [("#include <sys/klog.h>", "#include <sys/types.h>"),
                          ("#include <cstdlib>", "#include <sys/klog.h>")]:
            if inc not in s and anch in s:
                s = s.replace(anch, inc + "\n" + anch, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("kmsg dump inserted")

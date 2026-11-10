import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 1) includes
if "#include <sys/stat.h>" not in s:
    s = s.replace("#include <sys/klog.h>", "#include <sys/stat.h>\n#include <sys/klog.h>", 1)

# 2) 在 main 之前插入诊断函数（namespace init 内）
anchor = "int main(int argc, char** argv) {"
helper = r'''// [dsu-port] DSU 诊断：检查 zygote 依赖的关键路径
static void dsu_check_paths(const std::string& tag) {
    std::string out;
    const char* paths[] = {
        "/linkerconfig/ld.config.txt",
        "/linkerconfig",
        "/data",
        "/data/dalvik-cache",
        "/data/misc",
        "/apex/com.android.art",
        "/apex/com.android.art/bin",
        "/apex/com.android.art/lib64",
        "/system/bin/app_process64",
        "/system/bin/linker64",
        "/system/framework/services.jar",
        "/system/framework/framework-res.apk",
        "/metadata/gsi/dsu",
    };
    for (const char* p : paths) {
        struct stat st {};
        if (stat(p, &st) == 0) {
            out += std::string(p) + " OK size=" + std::to_string(st.st_size) +
                   " mode=" + std::to_string(st.st_mode & 07777) + "\n";
        } else {
            out += std::string(p) + " MISSING errno=" + std::to_string(errno) + "\n";
        }
    }
    out += "sys.boot_completed=" + android::base::GetProperty("sys.boot_completed", "") + "\n";
    out += "init.svc.zygote=" + android::base::GetProperty("init.svc.zygote", "") + "\n";
    out += "ro.zygote=" + android::base::GetProperty("ro.zygote", "") + "\n";
    out += "ro.crypto.state=" + android::base::GetProperty("ro.crypto.state", "") + "\n";
    out += "apexd.status=" + android::base::GetProperty("apexd.status", "") + "\n";
    android::base::WriteStringToFile(out, "/metadata/gsi/dsu/diag_" + tag);
}

'''
if "dsu_check_paths" not in s:
    s = s.replace(anchor, helper + anchor, 1)
    print("helper inserted")
else:
    print("helper already present")

# 3) 替换 zygote watch 线程：不 panic，写诊断
start_marker = "    // [dsu_zygote_watch]"
start = s.find(start_marker)
if start < 0:
    print("zygote watch block not found")
else:
    end_marker = "    }).detach();"
    end = s.find(end_marker, start)
    end += len(end_marker)
    new_block = '''    // [dsu_zygote_watch] DSU debug: 记录 zygote 状态变化与依赖检查，不 panic
    std::thread([] {
        std::string last_state;
        bool t15_done = false;
        for (int i = 0; i < 1200; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            auto st = android::base::GetProperty("init.svc.zygote", "");
            if (st != last_state) {
                LOG(ERROR) << "[dsu_zygote_watch] zygote state: " << last_state << " -> " << st
                           << " at tick " << i;
                if (st == "restarting" || st == "stopped") {
                    android::base::WriteStringToFile(st, "/metadata/gsi/dsu/zygote_last_state");
                    dsu_check_paths("zygote_fail_" + std::to_string(i));
                }
                last_state = st;
            }
            if (!t15_done && i >= 30) {
                t15_done = true;
                dsu_check_paths("t15");
            }
            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                dsu_check_paths("boot_completed");
                return;
            }
        }
    }).detach();'''
    s = s[:start] + new_block + s[end:]
    print("zygote watch replaced (no panic, diagnostics)")

io.open(P, "w", encoding="utf-8").write(s)
print("written, size:", len(s))

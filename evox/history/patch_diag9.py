#!/usr/bin/env python3
# 在服务器上给 init 打两个补丁：
#  1) init.cpp 诊断循环 v2：日志轮转 + 每轮清理旧文件，保证 /mnt/vendor/persist (27MB) 不撑爆，
#     并且始终保留最新一份完整 logcat 与 last_fatal.txt（tick 600 前也能看到崩溃原因）
#  2) property_service.cpp：强制 ro.product.cpu.abilist 为 64-bit only
#     （本镜像 64 位 only，但宿主 vendor 属性写 64+32，导致 PMS 调 dex2oat32 -> ENOENT/SIGABRT）
import re, sys

init_path = "/build/evox/system/core/init/init.cpp"
ps_path = "/build/evox/system/core/init/property_service.cpp"

src = open(init_path, encoding="utf-8", errors="replace").read()
changed = False

# ---- 0) 确保 include <glob.h> ----
if "#include <glob.h>" not in src:
    src = src.replace("#include <fcntl.h>", "#include <fcntl.h>\n#include <glob.h>", 1)
    if "#include <glob.h>" not in src:
        src = src.replace('#include <sys/stat.h>', '#include <sys/stat.h>\n#include <glob.h>', 1)
    changed = True

# ---- 1) 在 diag_started 之后插入清理逻辑 ----
anchor = 'android::base::WriteStringToFile("1", dsu_file("diag_started"));'
prune = anchor + '''
        // [dsu_diag2] 每轮启动先清理旧诊断文件：
        // /mnt/vendor/persist 只有 27MB，之前 logcat 5MB x 8 + kmsg 1MB x 13 直接把分区写满，
        // 导致 40s 之后完全没有日志、看不到 system_server 崩溃点。
        {
            const char* pats[] = {"logcat_*.log", "kmsg_*.log", "ps_*.txt", "mounts_*.txt",
                                  "props_*.txt", "sssockets_*.txt", "ssmountinfo_*.txt"};
            for (const char* pat : pats) {
                std::string full = dsu_file("");
                full += pat;
                glob_t g;
                if (glob(full.c_str(), 0, nullptr, &g) == 0) {
                    for (size_t gi = 0; gi < g.gl_pathc; ++gi) unlink(g.gl_pathv[gi]);
                }
                globfree(&g);
            }
        }'''
if "[dsu_diag2]" not in src:
    assert anchor in src
    src = src.replace(anchor, prune, 1)
    changed = True

# ---- 2) logcat 抓取：轮转 logcat_cur/logcat_prev + last_fatal.txt ----
old_logcat_start = "            if (tick == 10 || tick == 15 || tick == 20 || tick == 30 || tick == 45 || tick == 60 || tick == 90 || tick == 120) {"
old_logcat_body = '''                std::string tag = std::to_string(tick);
                pid_t lp = fork();
                if (lp == 0) {
                    std::string dst = dsu_file("logcat_" + tag + ".log");
                    int fd = open(dst.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
                    if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
                    execl("/system/bin/logcat", "logcat", "-b", "all", "-d", "-v", "threadtime", nullptr);
                    _exit(127);
                }
            }'''
new_logcat = '''            if (tick == 10 || tick == 20 || tick == 30 || tick == 45 || tick == 60 ||
                tick == 90 || tick == 120 || tick == 180 || tick == 240 || tick == 300 ||
                tick == 420 || tick == 540) {
                std::string base = dsu_file("");
                pid_t lp = fork();
                if (lp == 0) {
                    std::string cur = base + "logcat_cur.log";
                    std::string prev = base + "logcat_prev.log";
                    std::string fatal = base + "last_fatal.txt";
                    std::string cmd =
                        "mv -f '" + cur + "' '" + prev + "' 2>/dev/null; "
                        "/system/bin/logcat -b all -d -v threadtime > '" + cur + "' 2>&1; "
                        "/system/bin/logcat -b all -d -v threadtime 2>/dev/null | "
                        "grep -E 'FATAL EXCEPTION IN SYSTEM PROCESS|AndroidRuntime:|Watchdog|AudioPolicy|BOOT_COMPLETED|boot_completed' | "
                        "tail -100 > '" + fatal + "'";
                    execl("/system/bin/sh", "sh", "-c", cmd.c_str(), nullptr);
                    _exit(127);
                }
            }'''
if old_logcat_start in src:
    assert old_logcat_body in src, "logcat body not found"
    src = src.replace(old_logcat_body, new_logcat, 1)
    changed = True

# ---- 3) kmsg：轮转 kmsg_cur/kmsg_prev，减少 tick 次数 ----
old_kmsg_tick = "            if (tick == 1 || tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 40 || tick == 60 || tick == 120 || tick == 180 || tick == 240 || tick == 300 || tick == 420 || tick == 540) {"
new_kmsg_tick = "            if (tick == 5 || tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 540) {"
if old_kmsg_tick in src:
    src = src.replace(old_kmsg_tick, new_kmsg_tick, 1)
    changed = True

old_kmsg_write = '''                        int ofd = open((dsu_file("kmsg_") + tag + ".log").c_str(),
                                       O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);'''
new_kmsg_write = '''                        std::string kcur = dsu_file("kmsg_cur.log");
                        std::string kprev = dsu_file("kmsg_prev.log");
                        rename(kcur.c_str(), kprev.c_str());
                        int ofd = open(kcur.c_str(),
                                       O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);'''
if old_kmsg_write in src:
    src = src.replace(old_kmsg_write, new_kmsg_write, 1)
    changed = True

# ---- 4) ps 快照：减少次数、覆盖单文件 ----
old_ps_tick = "            if (tick <= 30 || tick == 45 || tick == 60 || tick == 90 || tick == 120) {"
new_ps_tick = "            if (tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420) {"
if old_ps_tick in src:
    src = src.replace(old_ps_tick, new_ps_tick, 1)
    changed = True

old_ps_write = 'android::base::WriteStringToFile(plist, dsu_file("ps_" + std::to_string(tick) + ".txt"));'
new_ps_write = 'android::base::WriteStringToFile(plist, dsu_file("ps_cur.txt"));'
if old_ps_write in src:
    src = src.replace(old_ps_write, new_ps_write, 1)
    changed = True

if changed:
    open(init_path, "w", encoding="utf-8").write(src)
    print("init.cpp patched")
else:
    print("init.cpp already patched (no changes)")

# ---- 5) property_service.cpp：强制 64-bit only abilist ----
psrc = open(ps_path, encoding="utf-8", errors="replace").read()
if "[dsu_force_abilist64]" not in psrc:
    anchor2 = '''        auto it = properties.find("ro.product.first_api_level");'''
    assert anchor2 in psrc
    add = '''        // [dsu_force_abilist64] 本镜像 /system 是 64-bit only（/system/lib 里没有 32 位库，
        // ART APEX 也没有 dex2oat32）。但宿主 vendor 属性把 abilist 写成 arm64+arm，
        // PMS 于是对含 32 位 native 库的包调 dex2oat32 -> ENOENT -> art_exec SIGABRT 刷屏。
        // 统一强制成 arm64-v8a；zygote rc 的 --abi-list 也必须同步一致。
        {
            LOG(INFO) << "[dsu-port] force ro.product.cpu.abilist=arm64-v8a (image is 64-bit only)";
            properties["ro.product.cpu.abilist"] = "arm64-v8a";
            properties["ro.product.cpu.abilist64"] = "arm64-v8a";
            auto it32 = properties.find("ro.product.cpu.abilist32");
            if (it32 != properties.end()) it32->second = "";
        }
''' + anchor2
    psrc = psrc.replace(anchor2, add, 1)
    open(ps_path, "w", encoding="utf-8").write(psrc)
    print("property_service.cpp patched")
else:
    print("property_service.cpp already patched")

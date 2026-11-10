#!/usr/bin/env python3
# b53 "日用版" init 补丁：
#   1) 新增 [dsu_daily] 模式（persist.sys.dsu_daily=1 时）：
#      - boot 完成后不自动重启回宿主 → 一直停在 EvoX
#      - 不写 logcat/kmsg/ps 大日志（/mnt/vendor/persist 是共享的 27MB 分区，宿主 MIUI 也用）
#      - 定期截断 svc_exit.log 防撑满
#   2) 非日用模式行为保持不变（调试镜像仍可自动回宿主 + 全量日志）
init_path = '/build/evox/system/core/init/init.cpp'
s = open(init_path, encoding='utf-8', errors='replace').read()

if '[dsu_daily]' in s:
    print('already patched')
    raise SystemExit(0)

# ---------- 1) 在 prune 块之后插入 daily 初始化 ----------
anchor1 = '''        for (int tick = 0; tick < 3600; ++tick) {  // [dsu_live_3600]  // [dsu_wd_1800]'''
daily_init = '''        // [dsu_daily] 日用模式（persist.sys.dsu_daily=1）：
        //  - /mnt/vendor/persist 只有 27MB，而且是宿主 MIUI 共用的分区，日用时不能写大日志
        //  - boot 完成后不再自动重启回宿主，一直停在 EvoX（想回 HyperOS 就手动重启手机）
        const bool dsu_daily =
            android::base::GetProperty("persist.sys.dsu_daily", "0") == "1";
        if (dsu_daily) {
            for (const char* f : {"svc_exit.log", "sockstat", "beat"}) {
                unlink(dsu_file(f).c_str());
            }
        }
''' + anchor1
assert anchor1 in s
s = s.replace(anchor1, daily_init, 1)

# ---------- 2) boot 完成分支：daily 不自动重启 ----------
old_boot = '''            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                // [dsu_boot_return] 首次完成启动：记录 + 留 240s 让 uicap 抓屏/抓 dumpsys，
                // 然后主动重启回宿主，避免等满 1800s 看门狗（每轮实验太慢）。
                android::base::WriteStringToFile("1", dsu_file("boot_completed_seen"));
                for (int w = 0; w < 1800; ++w) sleep(1);  // [dsu_live_3600]
                android::base::WriteStringToFile("reboot_after_boot", dsu_file("auto_reboot"));
                android::base::SetProperty("sys.powerctl", "reboot");
                _exit(0);
            }'''
new_boot = '''            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                // [dsu_boot_return] 首次完成启动：记录 + 留 240s 让 uicap 抓屏/抓 dumpsys，
                // 然后主动重启回宿主，避免等满 1800s 看门狗（每轮实验太慢）。
                android::base::WriteStringToFile("1", dsu_file("boot_completed_seen"));
                if (dsu_daily) {
                    // [dsu_daily] 日用模式：一直停在 EvoX，不自动回宿主
                    android::base::WriteStringToFile("stay_in_evox", dsu_file("auto_reboot"));
                    _exit(0);
                }
                for (int w = 0; w < 1800; ++w) sleep(1);  // [dsu_live_3600]
                android::base::WriteStringToFile("reboot_after_boot", dsu_file("auto_reboot"));
                android::base::SetProperty("sys.powerctl", "reboot");
                _exit(0);
            }'''
assert old_boot in s
s = s.replace(old_boot, new_boot, 1)

# ---------- 3) daily 下跳过 ps / logcat / kmsg 大 dump ----------
rep = [
    ('            if (tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 780) {',
     '            if (!dsu_daily && (tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 780)) {'),
    ('''            if (tick == 10 || tick == 20 || tick == 30 || tick == 45 || tick == 60 ||
                tick == 90 || tick == 120 || tick == 180 || tick == 240 || tick == 300 ||
                tick == 420 || tick == 540 || tick == 660 || tick == 780 ||
                tick == 960 || tick == 1200 || tick == 1500 || tick == 1800 || tick == 2400 || tick == 3000) {''',
     '''            if (!dsu_daily && (tick == 10 || tick == 20 || tick == 30 || tick == 45 || tick == 60 ||
                tick == 90 || tick == 120 || tick == 180 || tick == 240 || tick == 300 ||
                tick == 420 || tick == 540 || tick == 660 || tick == 780 ||
                tick == 960 || tick == 1200 || tick == 1500 || tick == 1800 || tick == 2400 || tick == 3000)) {'''),
    ('            if (tick == 5 || tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 540 || tick == 780 || tick == 1200) {',
     '            if (!dsu_daily && (tick == 5 || tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 540 || tick == 780 || tick == 1200)) {'),
]
for old, new in rep:
    assert old in s, 'missing anchor: ' + old[:60]
    s = s.replace(old, new, 1)

# ---------- 4) daily 下定期截断 svc_exit.log ----------
anchor4 = '''            {
                // [dsu_sockstat] 每 tick 记录 /dev/socket/zygote 状态 + system_server 的命名空间'''
add4 = '''            if (dsu_daily && tick % 60 == 0) {
                // [dsu_daily] 截断 service.cpp 写的 svc_exit.log，避免长会话撑满共享 persist 分区
                int sfd = open(dsu_file("svc_exit.log").c_str(), O_WRONLY | O_TRUNC | O_CLOEXEC);
                if (sfd >= 0) close(sfd);
            }
''' + anchor4
assert anchor4 in s
s = s.replace(anchor4, add4, 1)

open(init_path, 'w', encoding='utf-8').write(s)
print('daily-mode init patch applied')

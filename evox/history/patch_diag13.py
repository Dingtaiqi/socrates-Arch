#!/usr/bin/env python3
# init v6：boot_completed=1 后，留 240s 让 uicap 抓屏/抓状态，然后主动 reboot 回宿主。
# （否则 1800s 看门狗要等满 30 分钟，每轮迭代太慢）
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()
old = '''            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                android::base::WriteStringToFile("1", dsu_file("boot_completed_seen"));
                break;
            }'''
new = '''            if (android::base::GetProperty("sys.boot_completed", "") == "1") {
                // [dsu_boot_return] 首次完成启动：记录 + 留 240s 让 uicap 抓屏/抓 dumpsys，
                // 然后主动重启回宿主，避免等满 1800s 看门狗（每轮实验太慢）。
                android::base::WriteStringToFile("1", dsu_file("boot_completed_seen"));
                for (int w = 0; w < 240; ++w) sleep(1);
                android::base::WriteStringToFile("reboot_after_boot", dsu_file("auto_reboot"));
                android::base::SetProperty("sys.powerctl", "reboot");
                _exit(0);
            }'''
if '[dsu_boot_return]' in s:
    print('already patched')
elif old in s:
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('init v6: auto-reboot after boot_completed + 240s')
else:
    print('ANCHOR NOT FOUND')

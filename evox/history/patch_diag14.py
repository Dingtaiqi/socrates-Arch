#!/usr/bin/env python3
# init v7：
#  1) uicap 修好：screencap 放第一步并重试 3 次、带日志；补 wifi/bt/fingerprint/connectivity 等 dumps；
#     uicap_done 在 shell 里最后写（之前 execl 之后写不到）
#  2) boot_completed 后等待 240s -> 900s（留出 USB adb 实时调试窗口）
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

# ---- 1) 替换 uicap 块 ----
import re
start = s.find('    // [dsu_uicap]')
end = s.find('    // Copy logs captures from pstore.')
if start != -1 and end != -1 and end > start:
    new_block = '''    // [dsu_uicap] DSU 内没有 adb 时也能验证 UI/功能：boot_completed 后抓屏 + 关键 dumps
    if (fork() == 0) {
        for (int w = 0; w < 1700; ++w) {
            sleep(1);
            if (android::base::GetProperty("sys.boot_completed", "") == "1") break;
        }
        sleep(20);
        execl("/system/bin/sh", "sh", "-c",
              "L=/mnt/vendor/persist/dsu; "
              "i=0; while [ $i -lt 3 ]; do "
              "screencap -p $L/screen.png > $L/screencap_$i.log 2>&1; "
              "[ -s $L/screen.png ] && break; i=$((i+1)); sleep 10; done; "
              "dumpsys activity activities > $L/dump_activities.txt 2>&1; "
              "dumpsys window windows > $L/dump_windows.txt 2>&1; "
              "dumpsys connectivity > $L/dump_connectivity.txt 2>&1; "
              "dumpsys wifi > $L/dump_wifi.txt 2>&1; "
              "cmd wifi status > $L/wifi_status.txt 2>&1; "
              "dumpsys bluetooth_manager > $L/dump_bluetooth.txt 2>&1; "
              "dumpsys fingerprint > $L/dump_fingerprint.txt 2>&1; "
              "dumpsys media.audio_flinger > $L/dump_audio.txt 2>&1; "
              "service list > $L/service_list.txt 2>&1; "
              "getprop > $L/props_boot.txt 2>&1; "
              "ps -A -o PID,NAME > $L/ps_boot.txt 2>&1; "
              "echo \\"boot=$(getprop sys.boot_completed) adb=$(getprop init.svc.adbd) uicap=1\\" > $L/uicap_done",
              nullptr);
        _exit(0);
    }

'''
    s = s[:start] + new_block + s[end:]
    open(p, 'w', encoding='utf-8').write(s)
    print('uicap v7 replaced')
else:
    print('uicap block not found; start=%s end=%s' % (start, end))

# ---- 2) boot 后等待 240s -> 900s ----
s = open(p, encoding='utf-8', errors='replace').read()
if 'for (int w = 0; w < 900; ++w) sleep(1);' not in s:
    s = s.replace('for (int w = 0; w < 240; ++w) sleep(1);',
                  'for (int w = 0; w < 900; ++w) sleep(1);', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('post-boot wait -> 900s')
else:
    print('wait already 900s')

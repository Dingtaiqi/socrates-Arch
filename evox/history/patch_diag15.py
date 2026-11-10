#!/usr/bin/env python3
# init v8：uicap 修复（wake + dismiss-keyguard + timeout + ld.config 兜底诊断）
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

start = s.find('    // [dsu_uicap]')
execl_pos = s.find('execl("/system/bin/sh", "sh", "-c",', start)
end_marker = s.find('nullptr);', execl_pos)
if start == -1 or execl_pos == -1 or end_marker == -1:
    print('uicap block not found: start=%s execl=%s end=%s' % (start, execl_pos, end_marker))
    raise SystemExit(1)

new_execl = '''execl("/system/bin/sh", "sh", "-c",
              "L=/mnt/vendor/persist/dsu; "
              "input keyevent 224 >/dev/null 2>&1; "
              "wm dismiss-keyguard >/dev/null 2>&1; "
              "svc power stayon true >/dev/null 2>&1; "
              "sleep 2; "
              "i=0; while [ $i -lt 3 ]; do "
              "timeout 15 screencap -p $L/screen.png > $L/screencap_$i.log 2>&1; "
              "[ -s $L/screen.png ] && break; "
              "timeout 15 screencap -d 0 -p $L/screen.png >> $L/screencap_$i.log 2>&1; "
              "[ -s $L/screen.png ] && break; "
              "i=$((i+1)); sleep 8; done; "
              "if [ -s $L/screen.png ]; then echo \\"screen_ok=$(wc -c < $L/screen.png)\\" > $L/screencap_result.txt; "
              "else cp -f /linkerconfig/ld.config.txt $L/ld.config.txt 2>/dev/null; "
              "grep -A2 -B2 tethering /linkerconfig/ld.config.txt > $L/ldconfig_tethering.txt 2>&1; "
              "echo screen_fail > $L/screencap_result.txt; fi; "
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
              '''
s = s[:execl_pos] + new_execl + s[end_marker:]
open(p, 'w', encoding='utf-8').write(s)
print('uicap v8 applied')

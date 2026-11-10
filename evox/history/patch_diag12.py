#!/usr/bin/env python3
# init v5：把 DSU 看门狗 600s -> 1800s，并把诊断采样点扩展到 1800 tick。
# 依据 b45：字体卡点已过、system_server 跑到 PHASE_SYSTEM_SERVICES_READY/520，
# 日志末尾还在 dex2oat64，说明只是首次启动太慢，600s 看门狗在 boot_completed 前就重启了。
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()
changed = False

if '[dsu_wd_1800]' not in s:
    # 1) 主循环上界 900 -> 1800
    s = s.replace('for (int tick = 0; tick < 900; ++tick) {',
                  'for (int tick = 0; tick < 1800; ++tick) {  // [dsu_wd_1800]', 1)
    # 2) 看门狗 600 -> 1800
    s = s.replace('            if (tick == 600) {',
                  '            if (tick == 1800) {  // [dsu_wd_1800]', 1)
    changed = True

# 3) 扩展 logcat 采样点到 1800
old_lc = ('tick == 90 || tick == 120 || tick == 180 || tick == 240 || tick == 300 ||\n'
          '                tick == 420 || tick == 540) {')
new_lc = ('tick == 90 || tick == 120 || tick == 180 || tick == 240 || tick == 300 ||\n'
          '                tick == 420 || tick == 540 || tick == 660 || tick == 780 ||\n'
          '                tick == 960 || tick == 1200 || tick == 1500) {')
if old_lc in s and 'tick == 1500' not in s:
    s = s.replace(old_lc, new_lc, 1)
    changed = True

# 4) 扩展 kmsg/ps 采样点
old_k = 'if (tick == 5 || tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 540) {'
new_k = 'if (tick == 5 || tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 540 || tick == 780 || tick == 1200) {'
if old_k in s:
    s = s.replace(old_k, new_k, 1); changed = True
old_ps = 'if (tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420) {'
new_ps = 'if (tick == 20 || tick == 60 || tick == 120 || tick == 240 || tick == 420 || tick == 780) {'
if old_ps in s:
    s = s.replace(old_ps, new_ps, 1); changed = True

# 5) uicap：等 boot_completed 最多 1700s，然后截屏
old_wait = 'for (int w = 0; w < 120; ++w) {'
new_wait = 'for (int w = 0; w < 1700; ++w) {  // [dsu_wd_1800]'
if old_wait in s:
    s = s.replace(old_wait, new_wait, 1); changed = True

if changed:
    open(p, 'w', encoding='utf-8').write(s)
    print('init.cpp -> watchdog 1800s + extended sampling')
else:
    print('already patched')

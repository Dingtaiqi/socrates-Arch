#!/usr/bin/env python3
# init v9：给"实时调试会话"延长窗口：看门狗 1800 -> 3600s，boot 后回宿主 900 -> 1800s。
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()
if '[dsu_live_3600]' in s:
    print('already v9')
else:
    s = s.replace('for (int tick = 0; tick < 1800; ++tick) {',
                  'for (int tick = 0; tick < 3600; ++tick) {  // [dsu_live_3600]', 1)
    s = s.replace('if (tick == 1800) {  // [dsu_wd_1800]',
                  'if (tick == 3600) {  // [dsu_live_3600]', 1)
    s = s.replace('for (int w = 0; w < 900; ++w) sleep(1);',
                  'for (int w = 0; w < 1800; ++w) sleep(1);  // [dsu_live_3600]', 1)
    s = s.replace('tick == 960 || tick == 1200 || tick == 1500) {',
                  'tick == 960 || tick == 1200 || tick == 1500 || tick == 1800 || tick == 2400 || tick == 3000) {', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('init v9 applied: watchdog 3600s, post-boot window 1800s')

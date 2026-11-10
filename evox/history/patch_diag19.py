#!/usr/bin/env python3
# init v10：boot 后回宿主秒数 / 看门狗秒数 改为属性可调（同一 init 二进制复用）
#   persist.sys.dsu_return_after  (默认 1800；0=永不自动回，日用)
#   persist.sys.dsu_watchdog      (默认 3600；从未 boot_completed 时强制重启回宿主)
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_flex_wd]' in s:
    print('already patched')
    raise SystemExit(0)

anchor = '''        const bool dsu_daily =
            android::base::GetProperty("persist.sys.dsu_daily", "0") == "1";'''
add = anchor + '''
        // [dsu_flex_wd] 可调参数：这样调试镜像/日用镜像可以共用同一个 init 二进制
        int dsu_return_after = atoi(
            android::base::GetProperty("persist.sys.dsu_return_after", "1800").c_str());
        if (dsu_return_after < 0) dsu_return_after = 0;
        int dsu_watchdog_ticks = atoi(
            android::base::GetProperty("persist.sys.dsu_watchdog", "3600").c_str());
        if (dsu_watchdog_ticks <= 0 || dsu_watchdog_ticks > 3600) dsu_watchdog_ticks = 3600;'''
assert anchor in s
s = s.replace(anchor, add, 1)

o1 = 'for (int w = 0; w < 1800; ++w) sleep(1);  // [dsu_live_3600]'
n1 = 'for (int w = 0; w < dsu_return_after; ++w) sleep(1);  // [dsu_flex_wd]'
assert o1 in s
s = s.replace(o1, n1, 1)

o2 = 'if (tick == 3600) {  // [dsu_live_3600]'
n2 = 'if (tick == dsu_watchdog_ticks) {  // [dsu_flex_wd]'
assert o2 in s
s = s.replace(o2, n2, 1)

open(p, 'w', encoding='utf-8').write(s)
print('init v10 applied (flexible return_after / watchdog)')

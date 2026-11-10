#!/usr/bin/env python3
# init v11：DSU 模式改成"镜像内文件标记"判定，绕开 persist 属性在 init 早期读取的竞态/重复 key 问题。
#   /system/etc/dsu_daily_mode      -> 存在=日用（boot 后停留 EvoX，不自动回宿主）
#   /system/etc/dsu_quiet_mode      -> 存在=日志瘦身（不写 logcat/kmsg/ps 大文件）；默认跟随 daily
#   /system/etc/dsu_return_after    -> 文本数字：boot 后多少秒回宿主（默认 1800）
#   /system/etc/dsu_watchdog        -> 文本数字：看门狗秒数（默认 3600）
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_file_cfg]' in s:
    print('already v11')
    raise SystemExit(0)

old = '''        const bool dsu_daily =
            android::base::GetProperty("persist.sys.dsu_daily", "0") == "1";
        // [dsu_flex_wd] 可调参数：这样调试镜像/日用镜像可以共用同一个 init 二进制
        int dsu_return_after = atoi(
            android::base::GetProperty("persist.sys.dsu_return_after", "1800").c_str());
        if (dsu_return_after < 0) dsu_return_after = 0;
        int dsu_watchdog_ticks = atoi(
            android::base::GetProperty("persist.sys.dsu_watchdog", "3600").c_str());
        if (dsu_watchdog_ticks <= 0 || dsu_watchdog_ticks > 3600) dsu_watchdog_ticks = 3600;'''

new = '''        // [dsu_file_cfg] 用镜像内文件做判定，避免 persist 属性在 init 早期读取的竞态/重复 key 问题：
        //   /system/etc/dsu_daily_mode  存在 = 日用（boot 完成后停留，不自动回宿主）
        //   /system/etc/dsu_quiet_mode  存在 = 不写 logcat/kmsg/ps 大日志
        //   /system/etc/dsu_return_after / /system/etc/dsu_watchdog  文本数字，可选
        auto read_int_file = [](const char* path, int defv) -> int {
            std::string v;
            if (android::base::ReadFileToString(path, &v)) {
                int x = atoi(v.c_str());
                if (x > 0) return x;
            }
            return defv;
        };
        const bool dsu_daily = access("/system/etc/dsu_daily_mode", F_OK) == 0;
        const bool dsu_quiet = access("/system/etc/dsu_quiet_mode", F_OK) == 0 || dsu_daily;
        int dsu_return_after = read_int_file("/system/etc/dsu_return_after", 1800);
        if (dsu_daily) dsu_return_after = 0;
        int dsu_watchdog_ticks = read_int_file("/system/etc/dsu_watchdog", 3600);
        if (dsu_watchdog_ticks > 3600) dsu_watchdog_ticks = 3600;'''

assert old in s, 'v10 config block not found'
s = s.replace(old, new, 1)

# 用 dsu_quiet 替代 dsu_daily 控制日志/fd 截断
s = s.replace('if (dsu_daily && tick % 60 == 0) {', 'if (dsu_quiet && tick % 60 == 0) {', 1)
s = s.replace('if (!dsu_daily && (tick == 20 ||', 'if (!dsu_quiet && (tick == 20 ||', 1)
s = s.replace('if (!dsu_daily && (tick == 10 ||', 'if (!dsu_quiet && (tick == 10 ||', 1)
s = s.replace('if (!dsu_daily && (tick == 5 ||', 'if (!dsu_quiet && (tick == 5 ||', 1)
# daily 上电清理旧日志也按 quiet
s = s.replace('if (dsu_daily) {\n            for (const char* f : {"svc_exit.log", "sockstat", "beat"}) {',
              'if (dsu_quiet) {\n            for (const char* f : {"svc_exit.log", "sockstat", "beat"}) {', 1)
# boot 分支：daily 判断已经不再依赖属性
s = s.replace('if (dsu_daily) {\n                    // [dsu_daily] 日用模式：一直停在 EvoX，不自动回宿主',
              'if (dsu_daily) {\n                    // [dsu_daily] 日用模式：一直停在 EvoX，不自动回宿主', 1)

# 标记日志
s = s.replace('        for (int tick = 0; tick < 3600; ++tick) {  // [dsu_flex_wd]',
              '        android::base::WriteStringToFile(\n'
              '            std::string("daily=") + (dsu_daily ? "1" : "0") + " quiet=" + (dsu_quiet ? "1" : "0") +\n'
              '            " return_after=" + std::to_string(dsu_return_after) +\n'
              '            " watchdog=" + std::to_string(dsu_watchdog_ticks),\n'
              '            dsu_file("mode_info"));\n'
              '        for (int tick = 0; tick < 3600; ++tick) {  // [dsu_file_cfg]', 1)

open(p, 'w', encoding='utf-8').write(s)
print('init v11 [dsu_file_cfg] applied')

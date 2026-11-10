#!/usr/bin/env python3
# b51 init 补丁（v10）：
#  1) property_service.cpp: 强制 evox debug props（ro.adb.secure=0 / ro.debuggable=1 / service.adb.root=1），
#     加 [dsu_adb_secure0] 可 grep 标记字符串，便于检查 patch 是否进了 init 二进制。
#  2) init.cpp uicap: 改为执行镜像内脚本 /system/bin/dsu_uicap.sh（v10，含 WiFi 连接测试）
#  3) fs_diag guard: 阈值 10MB -> 16MB，每 10 tick -> 每 2 tick
ps_path = '/build/evox/system/core/init/property_service.cpp'
init_path = '/build/evox/system/core/init/init.cpp'

# ---------- 1) property_service.cpp ----------
s = open(ps_path, encoding='utf-8', errors='replace').read()
if '[dsu_adb_secure0]' in s:
    print('property_service already patched')
else:
    old = '''    std::string debug_value = GetProperty(DEBUG_PROP, "0");
    bool debug_enabled = debug_value == "1";'''
    new = '''    std::string debug_value = GetProperty(DEBUG_PROP, "0");
    // [dsu_adb_secure0] DSU 镜像固定打开 debug props：ro.adb.secure=0 让 adbd 不需要 USB 授权弹窗
    // （A17 的 adb_keys 预置校验不下发授权，弹窗没人点就永远 unauthorized）。
    bool debug_enabled = true;'''
    assert old in s, 'debug_enabled anchor not found'
    s = s.replace(old, new, 1)
    # 在设置循环前加可 grep 的 LOG 标记
    anchor = '''    for (const auto& [name, value] : debug_props) {'''
    mark = '''    LOG(INFO) << "[dsu_adb_secure0] forcing debug props: ro.adb.secure=0 ro.debuggable=1";
''' + anchor
    s = s.replace(anchor, mark, 1)
    open(ps_path, 'w', encoding='utf-8').write(s)
    print('property_service.cpp patched [dsu_adb_secure0]')

# ---------- 2) init.cpp uicap -> 执行脚本 ----------
s = open(init_path, encoding='utf-8', errors='replace').read()
start = s.find('    // [dsu_uicap]')
execl_pos = s.find('execl("/system/bin/sh", "sh", "-c",', start)
end_marker = s.find('nullptr);', execl_pos)
if start == -1 or execl_pos == -1 or end_marker == -1:
    print('uicap execl not found: start=%s execl=%s end=%s' % (start, execl_pos, end_marker))
else:
    new_execl = 'execl("/system/bin/sh", "sh", "/system/bin/dsu_uicap.sh", nullptr);'
    s = s[:execl_pos] + new_execl + s[end_marker + len('nullptr);'):]
    open(init_path, 'w', encoding='utf-8').write(s)
    print('init.cpp uicap -> /system/bin/dsu_uicap.sh')

# ---------- 3) fs_diag guard 阈值/频率 ----------
s = open(init_path, encoding='utf-8', errors='replace').read()
changed = False
if 'if (tick % 10 == 0) {\n                struct statvfs msv;' in s:
    s = s.replace('if (tick % 10 == 0) {\n                struct statvfs msv;',
                  'if (tick % 2 == 0) {\n                struct statvfs msv;', 1)
    changed = True
if 'low = free_bytes < (10ULL << 20);' in s:
    s = s.replace('low = free_bytes < (10ULL << 20);', 'low = free_bytes < (16ULL << 20);', 1)
    changed = True
if changed:
    open(init_path, 'w', encoding='utf-8').write(s)
    print('fs_diag guard: 16MB / every 2 ticks')
else:
    print('fs_diag guard pattern not found (maybe already changed)')

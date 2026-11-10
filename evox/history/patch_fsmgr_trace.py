import io
P = "/build/evox/system/fs/fs_mgr/fs_mgr.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

def repl(old, new, cnt=1):
    global s
    if old in s:
        s = s.replace(old, new, cnt)
        return True
    return False

# 1) 函数入口
r1 = repl("    int encryptable = FS_MGR_MNTALL_DEV_NOT_ENCRYPTABLE;\n    int error_count = 0;\n    CheckpointManager checkpoint_manager;",
          '    int encryptable = FS_MGR_MNTALL_DEV_NOT_ENCRYPTABLE;\n    int error_count = 0;\n    { int _t = mount_mode; dsu_trace("mount_all enter mode=" + std::to_string(_t)); }\n    CheckpointManager checkpoint_manager;')

# 2) 循环迭代
r2 = repl("        auto& current_entry = (*fstab)[i];\n",
          '        auto& current_entry = (*fstab)[i];\n        dsu_trace("iter " + std::to_string(i) + " " + current_entry.mount_point + " type=" + current_entry.fs_type + " blk=" + current_entry.blk_device);\n')

# 3) WaitForFile 前
r3 = repl("        if (current_entry.fs_mgr_flags.wait && !WaitForFile(current_entry.blk_device, 20s)) {",
          '        dsu_trace("wait_file " + current_entry.blk_device);\n        if (current_entry.fs_mgr_flags.wait && !WaitForFile(current_entry.blk_device, 20s)) {')

# 4) format 调用前
r4 = repl("            if (fs_mgr_do_format(*formattable_entry) == 0) {",
          '            dsu_trace("format_begin " + formattable_entry->mount_point);\n            if (fs_mgr_do_format(*formattable_entry) == 0) {')

# 5) format 之后（在 else 分支 log 之前）
r5 = repl("            } else {\n                LERROR << __FUNCTION__ << \"(): Format failed. \"",
          '            } else {\n                dsu_trace("format_failed " + formattable_entry->mount_point);\n                LERROR << __FUNCTION__ << "(): Format failed. "')

# 6) 函数退出
r6 = repl("    if (error_count) {\n        return FS_MGR_MNTALL_FAIL;\n    } else {\n        return encryptable;\n    }\n}\n\nint fs_mgr_umount_all",
          '    dsu_trace("mount_all exit enc=" + std::to_string(encryptable) + " err=" + std::to_string(error_count));\n    if (error_count) {\n        return FS_MGR_MNTALL_FAIL;\n    } else {\n        return encryptable;\n    }\n}\n\nint fs_mgr_umount_all')

print("patches:", r1, r2, r3, r4, r5, r6)
if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("written, trace count now:", s.count("dsu_trace"))
else:
    print("no changes")

import io

P = "/build/evox/system/fs/fs_mgr/fs_mgr.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 0) include + helper
if "dsu_trace" not in s:
    anchor = '#include "fs_mgr_priv.h"'
    if anchor in s:
        helper = '''#include <android-base/file.h>

// [dsu-port] step tracer for debugging DSU boot
static void dsu_trace(const std::string& msg) {
    android::base::WriteStringToFile(msg, "/metadata/gsi/dsu/fs_step");
}
'''
        s = s.replace(anchor, anchor + "\n" + helper, 1)
        print("helper inserted")
    else:
        print("WARN: anchor fs_mgr_priv.h not found")

# 1) /data entry 信息
old = '''        if (current_entry.fs_mgr_flags.logical) {
            if (!fs_mgr_update_logical_partition(&current_entry)) {'''
new = '''        if (current_entry.mount_point == "/data") {
            dsu_trace("data_entry blk=" + current_entry.blk_device + " fs=" + current_entry.fs_type +
                      " logical=" + std::to_string(current_entry.fs_mgr_flags.logical));
        }

        if (current_entry.fs_mgr_flags.logical) {
            if (!fs_mgr_update_logical_partition(&current_entry)) {'''
if old in s:
    s = s.replace(old, new, 1)
    print("data entry marker inserted")
else:
    print("WARN: data entry anchor not found")

# 2) mount_with_alternatives 前后
old = '''        bool mret = mount_with_alternatives(*fstab, i, encryption_interrupted, &last_idx_inspected,
                                            &attempted_idx);'''
new = '''        dsu_trace("before_mount_alternatives " + current_entry.mount_point);
        bool mret = mount_with_alternatives(*fstab, i, encryption_interrupted, &last_idx_inspected,
                                            &attempted_idx);
        dsu_trace("after_mount_alternatives " + current_entry.mount_point + " ret=" + std::to_string(mret));'''
if old in s:
    s = s.replace(old, new, 1)
    print("mount_with_alternatives markers inserted")
else:
    print("WARN: mwa anchor not found")

# 3) 跳过 /data 的 vdc encryptFstab（失败的格式化路径）
old = '''            if (should_use_metadata_encryption(current_entry) &&
                current_entry.mount_point == "/data") {'''
new = '''            // [dsu-port] DSU: skip vdc metadata-encryption setup for /data
            // (vdc -> vold -> keymaster/TZ hangs on this vendor under DSU)
            if (false && should_use_metadata_encryption(current_entry) &&
                current_entry.mount_point == "/data") {'''
if old in s:
    s = s.replace(old, new, 1)
    print("vdc encryptFstab branch skipped (/data)")
else:
    print("WARN: vdc encryptFstab anchor not found")

# 4) 跳过 /data 的 vdc mountFstab（mount 失败路径）
old = '''        if (mount_errno != EBUSY && mount_errno != EACCES && !encryption_interrupted &&
            should_use_metadata_encryption(attempted_entry)) {'''
new = '''        // [dsu-port] DSU: skip vdc mountFstab for /data
        if (false && mount_errno != EBUSY && mount_errno != EACCES && !encryption_interrupted &&
            should_use_metadata_encryption(attempted_entry)) {'''
if old in s:
    s = s.replace(old, new, 1)
    print("vdc mountFstab branch skipped")
else:
    print("WARN: vdc mountFstab anchor not found")

# 5) handle_encryptable: /data 直接当不加密
old = '''static int handle_encryptable(const FstabEntry& entry) {
    if (should_use_metadata_encryption(entry)) {'''
new = '''static int handle_encryptable(const FstabEntry& entry) {
    // [dsu-port] DSU: treat /data as non-encryptable (skip metadata encryption)
    if (entry.mount_point == "/data") {
        dsu_trace("handle_encryptable data -> NOT_ENCRYPTABLE");
        return FS_MGR_MNTALL_DEV_NOT_ENCRYPTABLE;
    }
    if (should_use_metadata_encryption(entry)) {'''
if old in s:
    s = s.replace(old, new, 1)
    print("handle_encryptable /data overridden")
else:
    print("WARN: handle_encryptable anchor not found")

io.open(P, "w", encoding="utf-8").write(s)
print("fs_mgr.cpp written")

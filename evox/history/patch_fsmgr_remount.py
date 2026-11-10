import io
P = "/build/evox/system/fs/fs_mgr/fs_mgr.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[dsu-port] remount data rw" in s:
    print("already patched")
else:
    old = '''        // Handle success and deal with encryptability.
        if (mret) {
            int status = handle_encryptable(attempted_entry);'''
    new = '''        // Handle success and deal with encryptability.
        if (mret) {
            // [dsu-port] DSU: /data 因 metadata encryption 标记被只读挂载，
            // 我们跳过 vdc 加密流程，这里直接 remount rw。
            if (attempted_entry.mount_point == "/data") {
                int rm = mount(nullptr, attempted_entry.mount_point.c_str(), nullptr,
                               MS_REMOUNT | MS_NOATIME, nullptr);
                LINFO << "[dsu-port] remount data rw ret=" << rm << " errno=" << errno;
            }
            int status = handle_encryptable(attempted_entry);'''
    if old in s:
        s = s.replace(old, new, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("fs_mgr remount patch inserted")
    else:
        print("anchor NOT found")

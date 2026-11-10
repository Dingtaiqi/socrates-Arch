import io
P = "/build/evox/system/fs/fs_mgr/fs_mgr.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[dsu-port] never mount data ro" in s:
    print("already patched")
else:
    old = "        const auto read_only = should_use_metadata_encryption(fstab[i]);"
    new = '''        // [dsu-port] DSU: /data 不走 metadata encryption，直接 rw 挂载
        const bool dsu_data = fstab[i].mount_point == "/data";
        const auto read_only = dsu_data ? false : should_use_metadata_encryption(fstab[i]);'''
    if old in s:
        s = s.replace(old, new, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("read_only override inserted")
    else:
        print("anchor NOT found")

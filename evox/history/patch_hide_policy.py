import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 在 SetupSelinux 调用之前插入隐藏宿主的 system_ext/product/odm sepolicy（仅 DSU 启动时）
if "[dsu-port] hide host sepolicy dirs" in s:
    print("already patched")
else:
    anchor = "SetupSelinux(argv);"
    if anchor not in s:
        print("SetupSelinux anchor NOT found")
    else:
        ins = '''    // [dsu-port] hide host sepolicy dirs (DSU 用宿主 system_ext/product，策略不兼容)
    if (access("/metadata/gsi/dsu/active", F_OK) == 0) {
        mkdir("/tmp_dsu_ext_selinux", 0755);
        mount("tmpfs", "/system_ext/etc/selinux", "tmpfs", MS_RDONLY, nullptr);
        mount("tmpfs", "/product/etc/selinux", "tmpfs", MS_RDONLY, nullptr);
    }
'''
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("hide-host-sepolicy patch inserted before", anchor)

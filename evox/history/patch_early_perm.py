import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

old = '    SetupSelinux(argv);\n    dsumark("/metadata/gsi/dsu/s2_main");'
new = '''    SetupSelinux(argv);
    // [dsu-port] 策略加载后立刻 permissive，否则 init 对 /metadata 的写会被 SELinux 拦
    {
        int pr0 = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
        LOG(ERROR) << "[dsu-port] early permissive result=" << pr0;
    }
    dsumark("/dev/.dsu_s2main");
    dsumark("/metadata/gsi/dsu/s2_main");'''
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("early permissive inserted")
else:
    print("anchor not found")

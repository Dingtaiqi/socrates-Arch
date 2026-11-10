import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
anchor = "int SecondStageMain(int argc, char** argv) {"
add = '''int SecondStageMain(int argc, char** argv) {
    // [dsu-port] 尝试 SELinux permissive，便于诊断与规避权限拦截
    {
        int r = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
        LOG(ERROR) << "[dsu-port] set permissive result=" << r;
    }
'''
if "[dsu-port] 尝试 SELinux permissive" in s:
    print("already patched")
elif anchor in s:
    s = s.replace(anchor, add, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("permissive patch inserted")
else:
    print("anchor not found")

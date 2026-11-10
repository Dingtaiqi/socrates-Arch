import io
P = "/build/evox/system/core/init/selinux.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 在 SelinuxSetEnforcement 里：DSU 启动时强制 permissive（此时仍是 kernel 域，有全部权限）
if "[dsu-port] SelinuxSetEnforcement" in s:
    print("already patched")
else:
    anchor = "void SelinuxSetEnforcement() {"
    if anchor not in s:
        print("anchor not found")
    else:
        ins = '''void SelinuxSetEnforcement() {
    // [dsu-port] DSU 启动时强制 permissive：宿主编译出的策略不允许 init 域 setenforce，
    // 但此处在 kernel 域（policy 加载后的 selinux_setup 阶段），写入一定成功。
    if (access("/metadata/gsi/dsu/active", F_OK) == 0) {
        int fd = open("/sys/fs/selinux/enforce", O_WRONLY | O_CLOEXEC);
        int wr = -1, we = 0;
        if (fd >= 0) {
            wr = (int)write(fd, "0", 1);
            we = errno;
            close(fd);
        }
        LOG(ERROR) << "[dsu-port] SelinuxSetEnforcement force permissive wr=" << wr
                   << " errno=" << we;
    }
'''
        s = s.replace(anchor, ins, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("SelinuxSetEnforcement patched")

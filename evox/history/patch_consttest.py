import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] const test" in s:
    print("already patched")
else:
    anchor = '''                LOG(ERROR) << "[du] rep done dir=" << d << " bad=" << bad;'''
    ins = anchor + '''
                if (d == 0) {
                    // 常量上下文对照测试：排除 ctx 字符串损坏的可能
                    const char* ctests[2] = {"u:object_r:properties_serial:s0",
                                             "u:object_r:adaptive_haptics_prop:s0"};
                    for (int ci = 0; ci < 2; ci++) {
                        char cpath[300];
                        snprintf(cpath, sizeof(cpath), "/dev/du_probe/c%d", ci);
                        unlink(cpath);
                        int cfd = open(cpath, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
                        errno = 0;
                        int cr = -1;
                        if (cfd >= 0) cr = fsetxattr(cfd, "security.selinux", ctests[ci],
                                                     strlen(ctests[ci]) + 1, 0);
                        LOG(ERROR) << "[du] const test ctx=" << ctests[ci] << " r=" << cr
                                   << " errno=" << errno;
                        if (cfd >= 0) close(cfd);
                    }
                }'''
    if anchor in s:
        s = s.replace(anchor, ins, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("const test inserted")
    else:
        print("anchor not found")

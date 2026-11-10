import io
P = "/build/evox/system/core/init/selinux.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

if "using host precompiled sepolicy" in s:
    print("already patched")
else:
    anchor = '''    LOG(INFO) << "Compiling SELinux policy";'''
    if anchor not in s:
        print("anchor not found")
    else:
        ins = '''    if (is_dsu_boot) {
        const char* host_pc = "/odm/etc/selinux/precompiled_sepolicy";
        if (access(host_pc, F_OK) == 0) {
            unique_fd pfd(open(host_pc, O_RDONLY | O_CLOEXEC | O_BINARY));
            if (pfd != -1) {
                LOG(INFO) << "[dsu-port] using host precompiled sepolicy " << host_pc;
                policy_file->fd = std::move(pfd);
                policy_file->path = host_pc;
                return true;
            }
        }
        LOG(ERROR) << "[dsu-port] host precompiled sepolicy missing, falling back to compile";
    }
'''
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("host precompiled policy patch inserted")

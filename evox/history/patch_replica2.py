import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] replica" in s:
    print("already patched")
else:
    anchor = '''    // [du] 尝试删掉 appcompat_override 目录，强制 bionic 跳过第二个 area 初始化'''
    ins = '''    // [du] replica: 复刻 bionic 每个 context 的 map_prop_area_rw 流程（主目录 + appcompat_override）
    {
        struct stat ast{};
        bool has_app = (stat("/dev/__properties__/appcompat_override", &ast) == 0);
        LOG(ERROR) << "[du] appcompat_override exists=" << has_app;
        const char* dirs[2] = {"/dev/__properties__", "/dev/__properties__/appcompat_override"};
        int n_dir = has_app ? 2 : 1;
        if (du_pi) {
            int du_n = du_pi->num_contexts();
            LOG(ERROR) << "[du] replica num_contexts=" << du_n;
            for (int d = 0; d < n_dir; ++d) {
                int bad = 0;
                for (int i = 0; i < du_n; ++i) {
                    const char* ctx = du_pi->context(i);
                    char path[300];
                    snprintf(path, sizeof(path), "%s/%s", dirs[d], ctx);
                    int fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0444);
                    if (fd < 0) {
                        LOG(ERROR) << "[du] rep open fail d=" << d << " ctx=" << ctx << " errno=" << errno;
                        bad++;
                        continue;
                    }
                    errno = 0;
                    int rx = fsetxattr(fd, "security.selinux", ctx, strlen(ctx) + 1, 0);
                    if (rx != 0) {
                        LOG(ERROR) << "[du] rep xattr fail d=" << d << " ctx=" << ctx << " errno=" << errno;
                        bad++;
                    }
                    errno = 0;
                    int rf = ftruncate(fd, 131072);
                    if (rf != 0) {
                        LOG(ERROR) << "[du] rep trunc fail ctx=" << ctx << " errno=" << errno;
                        bad++;
                    }
                    errno = 0;
                    void* rm = mmap(nullptr, 131072, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                    if (rm == MAP_FAILED) {
                        LOG(ERROR) << "[du] rep mmap fail ctx=" << ctx << " errno=" << errno;
                        bad++;
                    } else {
                        munmap(rm, 131072);
                    }
                    close(fd);
                    unlink(path);
                }
                LOG(ERROR) << "[du] rep done dir=" << d << " bad=" << bad;
            }
        } else {
            LOG(ERROR) << "[du] replica skipped: du_pi invalid";
        }
    }
''' + anchor
    if anchor in s:
        s = s.replace(anchor, ins, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("replica inserted")
    else:
        print("anchor not found")

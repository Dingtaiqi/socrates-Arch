import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] replica" in s:
    print("already patched")
else:
    # 在 rm appcompat 块前插入完整复刻循环
    anchor = '''    // [du] 尝试删掉 appcompat_override 目录，强制 bionic 跳过第二个 area 初始化'''
    ins = '''    // [du] replica: 完整复刻 bionic 每个 context 的 map_prop_area_rw 流程
    if (du_pi) {
        int du_n = du_pi->num_contexts();
        LOG(ERROR) << "[du] replica num_contexts=" << du_n;
        int bad = 0;
        for (int i = 0; i < du_n; ++i) {
            const char* ctx = du_pi->context(i);
            char path[300];
            snprintf(path, sizeof(path), "/dev/__properties__/%s", ctx);
            int fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0444);
            if (fd < 0) {
                LOG(ERROR) << "[du] replica open fail ctx=" << ctx << " errno=" << errno;
                bad++;
                continue;
            }
            errno = 0;
            int rx = fsetxattr(fd, "security.selinux", ctx, strlen(ctx) + 1, 0);
            if (rx != 0) {
                LOG(ERROR) << "[du] replica fsetxattr fail ctx=" << ctx << " errno=" << errno;
                bad++;
            }
            errno = 0;
            int rf = ftruncate(fd, 131072);
            if (rf != 0) {
                LOG(ERROR) << "[du] replica ftruncate fail ctx=" << ctx << " errno=" << errno;
                bad++;
            }
            errno = 0;
            void* rm = mmap(nullptr, 131072, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (rm == MAP_FAILED) {
                LOG(ERROR) << "[du] replica mmap fail ctx=" << ctx << " errno=" << errno;
                bad++;
            } else {
                munmap(rm, 131072);
            }
            close(fd);
            unlink(path);
        }
        LOG(ERROR) << "[du] replica done bad=" << bad;
    } else {
        LOG(ERROR) << "[du] replica skipped: du_pi invalid";
    }
''' + anchor
    if anchor in s:
        s = s.replace(anchor, ins, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("replica inserted")
    else:
        print("anchor not found")

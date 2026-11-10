import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

if "[du] probe fsetxattr" in s:
    print("already patched")
else:
    old = "    CreateSerializedPropertyInfo();\n    int du_ar = __system_property_area_init();"
    new = '''    CreateSerializedPropertyInfo();
    {
        struct stat du_st{};
        errno = 0;
        int du_sr = stat("/dev/__properties__/property_info", &du_st);
        LOG(ERROR) << "[du] stat property_info=" << du_sr << " errno=" << errno
                   << " size=" << (du_sr == 0 ? static_cast<long>(du_st.st_size) : -1L)
                   << " uid=" << (du_sr == 0 ? du_st.st_uid : 0)
                   << " gid=" << (du_sr == 0 ? du_st.st_gid : 0)
                   << " mode=" << (du_sr == 0 ? du_st.st_mode : 0);
        PropertyInfoAreaFile du_pi;
        bool du_ok = du_pi.LoadDefaultPath();
        LOG(ERROR) << "[du] LoadDefaultPath ok=" << du_ok;
        errno = 0;
        int du_fd = open("/dev/__properties__/_probe", O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
        LOG(ERROR) << "[du] probe open fd=" << du_fd << " errno=" << errno;
        if (du_fd >= 0) {
            const char* du_ctx = "u:object_r:properties_serial:s0";
            errno = 0;
            int du_x = fsetxattr(du_fd, "security.selinux", du_ctx, strlen(du_ctx) + 1, 0);
            LOG(ERROR) << "[du] probe fsetxattr=" << du_x << " errno=" << errno;
            errno = 0;
            int du_ft = ftruncate(du_fd, 131072);
            LOG(ERROR) << "[du] probe ftruncate=" << du_ft << " errno=" << errno;
            errno = 0;
            void* du_map = mmap(nullptr, 131072, PROT_READ | PROT_WRITE, MAP_SHARED, du_fd, 0);
            LOG(ERROR) << "[du] probe mmap=" << (du_map != MAP_FAILED) << " errno=" << errno;
            if (du_map != MAP_FAILED) munmap(du_map, 131072);
            close(du_fd);
        }
        errno = 0;
        int du_afd = open("/dev/__properties__/u:object_r:properties_serial:s0",
                          O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0444);
        LOG(ERROR) << "[du] probe ctxfile open fd=" << du_afd << " errno=" << errno;
        if (du_afd >= 0) {
            const char* du_ctx = "u:object_r:properties_serial:s0";
            errno = 0;
            int du_x2 = fsetxattr(du_afd, "security.selinux", du_ctx, strlen(du_ctx) + 1, 0);
            LOG(ERROR) << "[du] probe ctxfile fsetxattr=" << du_x2 << " errno=" << errno;
            close(du_afd);
        }
        errno = 0;
        LOG(ERROR) << "[du] probes done errno=" << errno;
    }
    int du_ar = __system_property_area_init();'''
    if old in s:
        s = s.replace(old, new, 1)
        # includes
        if "#include <sys/xattr.h>" not in s:
            s = s.replace('#include <sys/stat.h>', '#include <sys/stat.h>\n#include <sys/xattr.h>\n#include <sys/mman.h>', 1)
            if "#include <sys/xattr.h>" not in s:
                s = s.replace('#include "property_service.h"', '#include <sys/xattr.h>\n#include <sys/mman.h>\n#include "property_service.h"', 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("probe patch inserted")
    else:
        print("pattern NOT found")

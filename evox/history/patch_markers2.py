import io

# ---------- 1) init.cpp: 加 dsumark 辅助函数 + 关键 checkpoint ----------
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

if "dsumark" in s:
    print("init.cpp already patched")
else:
    # 辅助函数：插在 #include "selinux.h" 之后
    helper = '''
// [dsu-port] 低层进度标记：不依赖 libbase/property，直接 syscall 写文件
[[maybe_unused]] static void dsumark(const char* path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd >= 0) {
        (void)write(fd, "1", 1);
        close(fd);
    }
}
[[maybe_unused]] static void dsumark_str(const char* path, const std::string& text) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd >= 0) {
        (void)write(fd, text.data(), text.size());
        close(fd);
    }
}
'''
    s = s.replace('#include "selinux.h"', '#include "selinux.h"\n' + helper, 1)

    # a) main() 里 SetupSelinux 之后
    s = s.replace("    SetupSelinux(argv);",
                  '    SetupSelinux(argv);\n    dsumark("/metadata/gsi/dsu/s2_main");', 1)

    # b) SecondStageMain 开头（InitKernelLogging 之后）
    s = s.replace('    LOG(INFO) << "init second stage started!";',
                  '    LOG(INFO) << "init second stage started!";\n    dsumark("/dev/.dsu_s2");\n    dsumark("/metadata/gsi/dsu/s2_second");', 1)

    # c) PropertyInit 前
    s = s.replace("    PropertyInit();",
                  '    dsumark("/metadata/gsi/dsu/s2_preprop");\n    PropertyInit();\n    dsumark("/metadata/gsi/dsu/s2_postprop");', 1)

    # d) PropertyInit 之后几个阶段
    s = s.replace("    MountExtraFilesystems();",
                  '    dsumark("/metadata/gsi/dsu/s2_mounted_extra");\n    MountExtraFilesystems();\n    dsumark("/metadata/gsi/dsu/s2_after_extra");', 1)
    s = s.replace("    SelabelInitialize();",
                  '    dsumark("/metadata/gsi/dsu/s2_pre_selabel");\n    SelabelInitialize();\n    dsumark("/metadata/gsi/dsu/s2_post_selabel");', 1)
    s = s.replace("    StartPropertyService(&property_fd);",
                  '    dsumark("/metadata/gsi/dsu/s2_pre_propsvc");\n    StartPropertyService(&property_fd);\n    dsumark("/metadata/gsi/dsu/s2_post_propsvc");', 1)

    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp markers inserted")

# ---------- 2) property_service.cpp: 探针结果落盘 ----------
P2 = "/build/evox/system/core/init/property_service.cpp"
s2 = io.open(P2, encoding="utf-8", errors="replace").read()
if "probe_result.txt" in s2:
    print("property_service.cpp already patched")
else:
    old = '        LOG(ERROR) << "[du] probes done errno=" << errno;'
    new = '''        LOG(ERROR) << "[du] probes done errno=" << errno;
        {
            std::string rep;
            rep += "stat=" + std::to_string(du_sr) + " size=" +
                   std::to_string(du_sr == 0 ? static_cast<long>(du_st.st_size) : -1L) +
                   "\\nLoadDefaultPath=" + std::to_string(static_cast<int>(du_ok)) + "\\n";
            int fd2 = open("/dev/__properties__/_probe", O_RDONLY | O_CLOEXEC);
            rep += "probe_open_fd=" + std::to_string(fd2) + "\\n";
            if (fd2 >= 0) close(fd2);
            struct stat xst{};
            if (stat("/dev/__properties__/u:object_r:properties_serial:s0", &xst) == 0) {
                rep += "ctxfile_exists=1 size=" + std::to_string(static_cast<long>(xst.st_size)) +
                       " uid=" + std::to_string(xst.st_uid) + "\\n";
            } else {
                rep += "ctxfile_exists=0 errno=" + std::to_string(errno) + "\\n";
            }
            int fdx = open("/sys/fs/selinux/enforce", O_RDONLY | O_CLOEXEC);
            if (fdx >= 0) {
                char b[8] = {};
                (void)read(fdx, b, 7);
                close(fdx);
                rep += std::string("enforce=") + b + "\\n";
            }
            dsumark_str("/metadata/gsi/dsu/probe_result.txt", rep);
        }'''
    if old in s2:
        s2 = s2.replace(old, new, 1)
        io.open(P2, "w", encoding="utf-8").write(s2)
        print("property_service probe-result patch inserted")
    else:
        print("property_service pattern NOT found")

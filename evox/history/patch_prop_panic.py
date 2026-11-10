import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] panic for dump" in s:
    print("already patched")
else:
    old = '''    if (du_ar) {
        LOG(ERROR) << "[du] property area failed (continuing permissive debug) errno=" << du_ar_errno;
    }'''
    new = '''    if (du_ar) {
        LOG(ERROR) << "[du] property area failed errno=" << du_ar_errno;
        LOG(ERROR) << "[du] panic for dump (capture kmsg via minidump)";
        int du_fd = open("/proc/sysrq-trigger", O_WRONLY | O_CLOEXEC);
        if (du_fd >= 0) { (void)write(du_fd, "c", 1); close(du_fd); }
    }'''
    if old in s:
        s = s.replace(old, new, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("panic patch inserted")
    else:
        print("pattern NOT found")

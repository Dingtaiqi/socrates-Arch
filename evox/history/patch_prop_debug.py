import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] property_area" in s:
    print("already patched")
else:
    old = '''    mkdir("/dev/__properties__", S_IRWXU | S_IXGRP | S_IXOTH);
    CreateSerializedPropertyInfo();
    if (__system_property_area_init()) {
        LOG(FATAL) << "Failed to initialize property area";
    }'''
    new = '''    int du_mk = mkdir("/dev/__properties__", S_IRWXU | S_IXGRP | S_IXOTH);
    int du_mk_errno = errno;
    LOG(ERROR) << "[du] mkdir __properties__ ret=" << du_mk << " errno=" << du_mk_errno;
    {
        int du_w = access("/dev", W_OK);
        LOG(ERROR) << "[du] /dev W_OK=" << du_w << " errno=" << errno;
        struct statvfs du_vfs;
        if (statvfs("/dev", &du_vfs) == 0) {
            LOG(ERROR) << "[du] /dev flags=" << du_vfs.f_flag << " bavail=" << du_vfs.f_bavail;
        } else {
            LOG(ERROR) << "[du] statvfs /dev failed errno=" << errno;
        }
    }
    CreateSerializedPropertyInfo();
    int du_ar = __system_property_area_init();
    int du_ar_errno = errno;
    LOG(ERROR) << "[du] property_area_init ret=" << du_ar << " errno=" << du_ar_errno;
    if (du_ar) {
        LOG(ERROR) << "[du] property area failed (continuing permissive debug) errno=" << du_ar_errno;
    }'''
    if old in s:
        s = s.replace(old, new, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("PropertyInit instrumentation inserted")
    else:
        print("pattern NOT found")

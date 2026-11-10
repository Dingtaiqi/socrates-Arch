import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[dsu-port] hidden host property_contexts" in s:
    print("already patched")
else:
    anchor = "    PropertyInit();"
    if anchor not in s:
        print("anchor not found")
    else:
        ins = '''    // [dsu-port] hide host selinux dirs before property area init (property_contexts mismatch)
    if (access("/metadata/gsi/dsu/active", F_OK) == 0) {
        const char* dirs[] = {"/vendor/etc/selinux", "/odm/etc/selinux",
                              "/system_ext/etc/selinux", "/product/etc/selinux", nullptr};
        int hidden = 0;
        for (int i = 0; dirs[i]; ++i) {
            if (mount("tmpfs", dirs[i], "tmpfs", MS_RDONLY, nullptr) == 0) hidden++;
        }
        LOG(ERROR) << "[dsu-port] hidden host property_contexts dirs count=" << hidden;
    }
'''
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("hide property_contexts patch inserted")

import io
P = "/build/evox/system/core/init/selinux.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

if "is_dsu_boot" in s:
    print("already patched")
else:
    # 1) 在编译前定义 is_dsu_boot
    anchor1 = "    LOG(INFO) << \"Compiling SELinux policy\";"
    if anchor1 not in s:
        print("anchor1 NOT found")
    else:
        s = s.replace(anchor1, '''    const bool is_dsu_boot = (access("/metadata/gsi/dsu/active", F_OK) == 0);
    if (is_dsu_boot) {
        LOG(INFO) << "[dsu-port] DSU boot: skipping host system_ext/product/odm sepolicy";
    }
''' + anchor1, 1)

        # 2) 在 odm_policy_cil_file 定义之后清空宿主策略
        anchor2 = "    const std::string version_as_string = std::to_string(SEPOLICY_VERSION);"
        if anchor2 in s:
            s = s.replace(anchor2, '''    if (is_dsu_boot) {
        system_ext_policy_cil_file.clear();
        system_ext_mapping_file.clear();
        system_ext_compat_cil_file.clear();
        product_policy_cil_file.clear();
        product_mapping_file.clear();
        odm_policy_cil_file.clear();
    }
''' + anchor2, 1)
            print("patch inserted")
        else:
            print("anchor2 NOT found")

        io.open(P, "w", encoding="utf-8").write(s)

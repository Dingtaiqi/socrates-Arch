import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s
if "dsu_force_first_api_level" in s:
    print("already")
else:
    anchor = '''    initialize_microdroid_properties(&properties);'''
    if anchor in s:
        ins = '''    initialize_microdroid_properties(&properties);
    {
        // [dsu_force_first_api_level] DSU 只替换 /system，宿主 /product、/system_ext 的 MIUI 应用与
        // 镜像 AOSP 应用签名不同却同用 android.uid.system。AOSP 在 first_api_level > 29 时把该
        // 签名不一致视为致命错误（system_server 崩溃）。降级为 <= 29 时只会跳过冲突包。
        auto it = properties.find("ro.product.first_api_level");
        if (it != properties.end()) {
            LOG(INFO) << "[dsu-port] override ro.product.first_api_level " << it->second << " -> 29";
            it->second = "29";
        } else {
            properties["ro.product.first_api_level"] = "29";
            LOG(INFO) << "[dsu-port] inject ro.product.first_api_level=29";
        }
    }
'''
        s = s.replace(anchor, ins, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("patched")
    else:
        print("anchor not found")
if s != orig:
    print("changed")

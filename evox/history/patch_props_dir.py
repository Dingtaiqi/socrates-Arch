import io
P = "/build/evox/system/core/init/property_service.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[du] dumped props dir" in s:
    print("already patched")
else:
    old = '''    int du_ar = __system_property_area_init();
    int du_ar_errno = errno;'''
    new = '''    // [du] 尝试删掉 appcompat_override 目录，强制 bionic 跳过第二个 area 初始化
    {
        int du_rm = system("rm -rf /dev/__properties__/appcompat_override");
        LOG(ERROR) << "[du] rm appcompat_override ret=" << du_rm;
    }
    int du_ar = __system_property_area_init();
    int du_ar_errno = errno;
    // [du] 落盘 /dev/__properties__ 目录清单
    {
        std::string listing;
        DIR* d = opendir("/dev/__properties__");
        if (d) {
            int cnt = 0;
            struct dirent* e;
            while ((e = readdir(d)) != nullptr) {
                if (e->d_name[0] == '.') continue;
                cnt++;
                if (listing.size() < 120000) {
                    listing += e->d_name;
                    listing += "\\n";
                }
            }
            closedir(d);
            listing = "count=" + std::to_string(cnt) + "\\n" + listing;
        } else {
            listing = "opendir failed errno=" + std::to_string(errno);
        }
        android::base::WriteStringToFile(listing, "/metadata/gsi/dsu/props_dir.txt");
        LOG(ERROR) << "[du] dumped props dir count lines";
    }'''
    if old in s:
        s = s.replace(old, new, 1)
        if "#include <dirent.h>" not in s:
            s = s.replace('#include "property_service.h"', '#include <dirent.h>\n#include "property_service.h"', 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("appcompat-remove + dir dump inserted")
    else:
        print("pattern NOT found")

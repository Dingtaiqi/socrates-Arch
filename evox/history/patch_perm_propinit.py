import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "[dsu-port] permissive before PropertyInit" in s:
    print("already patched")
else:
    anchor = "    PropertyInit();"
    if anchor not in s:
        print("anchor not found")
    else:
        ins = '''    // [dsu-port] permissive before PropertyInit (host policy vs our image labels)
    {
        int pr = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
        LOG(ERROR) << "[dsu-port] permissive before PropertyInit result=" << pr;
    }
'''
        s = s.replace(anchor, ins + anchor, 1)
        io.open(P, "w", encoding="utf-8").write(s)
        print("permissive patch inserted")

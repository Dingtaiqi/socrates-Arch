import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = '''            if (i == 10) {
                int pr = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
                LOG(ERROR) << "[dsu-port] delayed permissive result=" << pr;
            }
'''
if old in s:
    s = s.replace(old, "", 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("delayed permissive removed")
elif "/sys/fs/selinux/enforce" in s:
    print("some permissive code remains!")
else:
    print("no permissive code found (ok)")

import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 1) 删除开头就设 permissive 的代码块
old = '''    // [dsu-port] 尝试 SELinux permissive，便于诊断与规避权限拦截
    {
        int r = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
        LOG(ERROR) << "[dsu-port] set permissive result=" << r;
    }
'''
if old in s:
    s = s.replace(old, "", 1)
    print("early permissive removed")
else:
    print("early permissive block not found")

# 2) 在 diag 线程里，tick>=10 (5s) 时设 permissive
kw = "if (!t15_done && i >= 30) {"
if kw in s:
    ins = '''if (i == 10) {
                    int pr = android::base::WriteStringToFile("0", "/sys/fs/selinux/enforce");
                    LOG(ERROR) << "[dsu-port] delayed permissive result=" << pr;
                }
                ''' + kw
    s = s.replace(kw, ins, 1)
    print("delayed permissive inserted")
else:
    print("t15 anchor not found")

io.open(P, "w", encoding="utf-8").write(s)

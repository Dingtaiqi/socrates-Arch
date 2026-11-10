import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 在 diag 线程循环末尾加自动重启（tick 250）
anchor = '''            if (tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {'''
if anchor in s:
    # 在循环体最后（tick 240 处理块之后）加：简化——直接在循环体开头判断 tick==250
    ins = '''            if (tick == 250) {
                android::base::WriteStringToFile("reboot_at_250", "/metadata/gsi/dsu/auto_reboot");
                android::base::SetProperty("sys.powerctl", "reboot");
                return;
            }
'''
    # 插到 tick==2 那行之前
    s = s.replace(anchor, ins + anchor, 1)
    print("auto-reboot inserted")
else:
    print("anchor not found")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)

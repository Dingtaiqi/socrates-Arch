import io

P = "/build/evox/system/core/init/action.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 删除旧的 trace 块（raw fd 与 WriteStringToFile 两个版本都可能存在）
import re
pat = re.compile(r"\n    // \[dsu-port\] trace.*?\n    \}\n", re.S)
s2, n = pat.subn("\n", s)
if n:
    print("removed old trace blocks:", n)
else:
    print("no old trace block found (ok)")

# 在 ExecuteCommand 开头插入 t_last 探针
anchor = "void Action::ExecuteCommand(const Command& command) const {\n    android::base::Timer t;\n"
newblk = '''void Action::ExecuteCommand(const Command& command) const {
    android::base::Timer t;
    // [dsu-port] t_last: 记录最后执行到的命令，用于定位 DSU 启动卡死点
    {
        std::string trigger_name2 = BuildTriggersString();
        if (trigger_name2.find("early-init") != std::string::npos) {
            std::string cmd_str2 = command.BuildCommandString();
            std::string rec = trigger_name2 + " | " + filename_ + ":" +
                              std::to_string(command.line()) + " | " + cmd_str2;
            android::base::WriteStringToFile(rec, "/metadata/gsi/dsu/t_last");
        }
    }
'''
if "[dsu-port] t_last" in s2:
    print("already has t_last")
elif anchor in s2:
    s2 = s2.replace(anchor, newblk, 1)
    io.open(P, "w", encoding="utf-8").write(s2)
    print("patched t_last probe")
else:
    print("ANCHOR NOT FOUND")

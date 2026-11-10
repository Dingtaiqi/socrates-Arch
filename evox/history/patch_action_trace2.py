import io

P = "/build/evox/system/core/init/action.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

# 找到已插入的 trace 块并替换为 WriteStringToFile 版本
start = s.find("    // [dsu-port] trace every command to /metadata for DSU debugging")
end = s.find("    auto result = command.InvokeFunc(subcontext_);", start)
if start < 0 or end < 0:
    print("trace block not found; start=%d end=%d" % (start, end))
else:
    newblk = '''    // [dsu-port] trace commands for DSU debugging (WriteStringToFile: proven path)
    {
        std::string trigger_name = BuildTriggersString();
        if (trigger_name.find("early-init") != std::string::npos ||
            trigger_name == "init" || trigger_name.find("m_") != std::string::npos) {
            std::string cmd_str = command.BuildCommandString();
            static std::string trace_accum;
            trace_accum += trigger_name + " | " + filename_ + ":" +
                           std::to_string(command.line()) + " | " + cmd_str + "\\n";
            if (trace_accum.size() > 200000) {
                trace_accum.erase(0, trace_accum.size() - 150000);
            }
            android::base::WriteStringToFile(trace_accum, "/metadata/gsi/dsu/trace.log");
        }
    }
'''
    s = s[:start] + newblk + s[end:]
    io.open(P, "w", encoding="utf-8").write(s)
    print("trace rewritten (WriteStringToFile)")

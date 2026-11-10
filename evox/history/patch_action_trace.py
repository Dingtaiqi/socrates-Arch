import io

P = "/build/evox/system/core/init/action.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()

old = "void Action::ExecuteCommand(const Command& command) const {\n    android::base::Timer t;\n    auto result = command.InvokeFunc(subcontext_);"
new = """void Action::ExecuteCommand(const Command& command) const {
    android::base::Timer t;
    // [dsu-port] trace every command to /metadata for DSU debugging
    {
        std::string trigger_name = BuildTriggersString();
        std::string cmd_str = command.BuildCommandString();
        std::string trace = trigger_name + " | " + filename_ + ":" +
                            std::to_string(command.line()) + " | " + cmd_str + "\\n";
        int tfd = open("/metadata/gsi/dsu/trace.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (tfd >= 0) {
            (void)write(tfd, trace.data(), trace.size());
            close(tfd);
        }
    }
    auto result = command.InvokeFunc(subcontext_);"""

if "[dsu-port] trace every command" in s:
    print("already patched")
elif old in s:
    s = s.replace(old, new, 1)
    # includes
    for inc, anchor in [("#include <fcntl.h>", '#include "action.h"'),
                        ("#include <unistd.h>", '#include <fcntl.h>')]:
        if inc not in s:
            s = s.replace(anchor, inc + "\n" + anchor, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched action.cpp")
else:
    print("PATTERN NOT FOUND")
    idx = s.find("void Action::ExecuteCommand")
    print(s[idx:idx+400] if idx >= 0 else "no ExecuteCommand")

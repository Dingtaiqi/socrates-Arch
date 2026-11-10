import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = "static Result<void> wait_for_coldboot_done_action(const BuiltinArguments& args) {"
new = "[[maybe_unused]] static Result<void> wait_for_coldboot_done_action(const BuiltinArguments& args) {"
if new in s:
    print("already patched")
elif old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched maybe_unused")
else:
    print("PATTERN NOT FOUND")

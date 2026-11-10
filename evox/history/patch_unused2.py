import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
if "static void dsu_check_paths" in s and "[[maybe_unused]] static void dsu_check_paths" not in s:
    s = s.replace("static void dsu_check_paths(", "[[maybe_unused]] static void dsu_check_paths(", 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("marked maybe_unused")
else:
    print("pattern state:", "maybe_unused" in s)

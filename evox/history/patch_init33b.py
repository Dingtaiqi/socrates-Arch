import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
import re
m = re.search(r"for \(int i = 0; i < (\d+); \+\+i\) \{", s)
print("current watchdog loop:", m.group(0) if m else "not found")
if m and m.group(1) != "180":
    s = s.replace(m.group(0), "for (int i = 0; i < 180; ++i) {", 1)
    s = re.sub(r"boot not completed in \d+s", "boot not completed in 180s", s)
    io.open(P, "w", encoding="utf-8").write(s)
    print("watchdog set 180s")
elif m:
    print("already 180s")

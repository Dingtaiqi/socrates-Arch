import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s
s = s.replace("if (tick == 20 || tick == 60 || tick == 120 || tick == 240) {",
              "if (tick == 2 || tick == 5 || tick == 10 || tick == 20 || tick == 60 || tick == 120 || tick == 240) {", 1)
if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("early dumps added")
else:
    print("pattern not found")

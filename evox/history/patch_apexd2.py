import io
P = "/build/evox/system/apex/apexd/apex_file.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = "O_WRONLY | O_CLOEXEC | O_CREAT | O_EXCL | O_SYNC, 0644"
new = "O_WRONLY | O_CLOEXEC | O_CREAT | O_EXCL, 0644  /* dsu-port drop O_SYNC */"
if "dsu-port drop O_SYNC" in s:
    print("already patched")
elif old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched OK")
else:
    print("STILL NOT FOUND")

import io
P = "/build/evox/system/apex/apexd/apex_file.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
old = "O_WRONLY | O_CLOEXEC | O_CREAT | O_EXCL | O_SYNC, 0644);"
new = "O_WRONLY | O_CLOEXEC | O_CREAT | O_EXCL, 0644);  // [dsu-port] drop O_SYNC (EIO workaround)"
if old in s:
    s = s.replace(old, new, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("patched O_SYNC removal")
elif "dsu-port" in s:
    print("already patched")
else:
    print("PATTERN NOT FOUND")

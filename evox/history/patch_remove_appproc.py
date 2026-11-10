import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 找到 tick == 40 的调试 fork 块并整块删除
start_marker = '''            if (tick == 40) {
                // [dsu-port] fork+exec app_process，stderr -> persist 共享分区'''
if start_marker in s:
    start = s.find(start_marker)
    # 找到匹配的结束：下一个 "            if (tick == 1 ||"
    end_marker = '''            if (tick == 1 || tick == 2 || tick == 5 || tick == 10'''
    end = s.find(end_marker, start)
    if end > start:
        removed = s[start:end]
        s = s[:start] + s[end:]
        io.open(P, "w", encoding="utf-8").write(s)
        print("removed debug app_process fork block, bytes:", len(removed))
    else:
        print("end marker not found")
else:
    print("start marker not found (maybe already removed)")

if s != orig:
    print("changed")

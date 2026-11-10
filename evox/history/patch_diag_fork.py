import io
P = "/build/evox/system/core/init/init.cpp"
s = io.open(P, encoding="utf-8", errors="replace").read()
orig = s

# 1) 线程开头 → fork 子进程
old_start = '''    // [dsu_diag] 单线程诊断：定时记录属性/挂载/内核日志，不 panic
    std::thread([] {
        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/diag_started");'''
new_start = '''    // [dsu_diag] 用 fork 子进程做诊断（不能用线程：setns(CLONE_NEWNS) 在
    // 多线程 init 中会返回 EINVAL，导致 enter_default_mount_ns 失败）
    pid_t dsu_diag_pid = fork();
    if (dsu_diag_pid == 0) {
        android::base::WriteStringToFile("1", "/metadata/gsi/dsu/diag_started");'''
if old_start in s:
    s = s.replace(old_start, new_start, 1)
    print("thread start replaced with fork")
elif "dsu_diag_pid" in s:
    print("already forked")
else:
    print("START anchor NOT found")

# 2) 线程结尾 → 子进程 _exit(0)
old_end = '''            }
        }
    }).detach();

    // Copy logs captures from pstore. Flush the logs when boot completes'''
new_end = '''            }
        }
        _exit(0);
    }

    // Copy logs captures from pstore. Flush the logs when boot completes'''
if old_end in s:
    s = s.replace(old_end, new_end, 1)
    print("thread end replaced with _exit")
elif "_exit(0);" in s and "dsu_diag_pid" in s:
    print("already forked end")
else:
    print("END anchor NOT found")

if s != orig:
    io.open(P, "w", encoding="utf-8").write(s)
    print("init.cpp updated")
else:
    print("NO CHANGE")

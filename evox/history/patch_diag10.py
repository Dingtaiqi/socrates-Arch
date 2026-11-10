#!/usr/bin/env python3
# init 诊断循环 v3：每 10 tick 检查一次 /metadata 可用空间，不足 6MB 就把 fs_diag.log 截断。
# fs_diag.log 是 DSU 里某个 kernel-domain 的 "init" 线程每 ~0.5s 追加 kmsg 写出来的（23MB），
# 该写入方持有早已打开的 fd，所以 early-init 里 bind mount /dev/null 覆盖路径拦不住；
# 但定期 ftruncate(0) 能释放已分配块（后续写入变稀疏），足以避免 /metadata 100% 满。
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_fsdiag_guard]' in s:
    print('already patched')
else:
    anchor = '''            if (tick % 1 == 0) {'''
    guard = '''            // [dsu_fsdiag_guard] /metadata 只有 62MB，某个 kernel-domain 写入方每 ~0.5s
            // 向 /metadata/fs_diag.log 追加 kmsg（实测长到 23MB），导致 gsi/dsu 状态写入 ENOSPC。
            // 写入方持有已打开的 fd，bind mount 覆盖路径无效，只能定期截断释放已分配块。
            if (tick % 10 == 0) {
                struct statvfs msv;
                if (statvfs("/metadata", &msv) == 0) {
                    unsigned long long free_bytes =
                        (unsigned long long)msv.f_bavail * (unsigned long long)msv.f_frsize;
                    if (free_bytes < (6ULL << 20)) {
                        truncate("/metadata/fs_diag.log", 0);
                        android::base::WriteStringToFile(
                            std::to_string(free_bytes),
                            dsu_file("fsdiag_guard_fired"));
                    }
                }
            }
''' + anchor
    assert anchor in s, 'anchor not found'
    s = s.replace(anchor, guard, 1)
    if '#include <sys/statvfs.h>' not in s:
        s = s.replace('#include <sys/stat.h>', '#include <sys/stat.h>\n#include <sys/statvfs.h>', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('init.cpp patched with fsdiag guard')

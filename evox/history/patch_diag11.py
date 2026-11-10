#!/usr/bin/env python3
# init 诊断循环 v4：
#  1) fs_diag 清理改成 "扫描 /proc/*/fd/* 找指向 /metadata/fs_diag.log 的 fd 并 ftruncate(0)"
#     （实测写入方是宿主持有已打开 fd 的进程，路径 truncate/rm 都无法释放空间）
#  2) 增加开机后自动采集：boot_completed 后 60s 抓 screencap + dumpsys activity/window 到 persist，
#     方便验证 UI 是否真的起来（DSU 内 adb 用不了）。
p = '/build/evox/system/core/init/init.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

old_guard = '''            // [dsu_fsdiag_guard] /metadata 只有 62MB，某个 kernel-domain 写入方每 ~0.5s
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
'''

new_guard = '''            // [dsu_fsdiag_guard] /metadata 只有 62MB，有一个 comm=init 的进程每 ~0.5s
            // 向 /metadata/fs_diag.log 追加 kmsg（实测长到 23MB），导致 gsi/dsu 状态写入 ENOSPC。
            // 关键：写入方持有的是早已打开的 fd，按路径 truncate/rm 都不会释放空间，
            // 必须扫描 /proc/<pid>/fd/* 找到指向该文件的 fd，对进程的 fd 1 做 ftruncate。
            if (tick % 10 == 0) {
                struct statvfs msv;
                bool low = false;
                if (statvfs("/metadata", &msv) == 0) {
                    unsigned long long free_bytes =
                        (unsigned long long)msv.f_bavail * (unsigned long long)msv.f_frsize;
                    low = free_bytes < (10ULL << 20);
                    if (low) {
                        android::base::WriteStringToFile(
                            std::to_string(free_bytes), dsu_file("fsdiag_guard_fired"));
                    }
                }
                if (low) {
                    DIR* mpd = opendir("/proc");
                    if (mpd) {
                        struct dirent* mde;
                        while ((mde = readdir(mpd)) != nullptr) {
                            if (mde->d_name[0] < '0' || mde->d_name[0] > '9') continue;
                            std::string fddir = std::string("/proc/") + mde->d_name + "/fd";
                            DIR* fdpd = opendir(fddir.c_str());
                            if (!fdpd) continue;
                            struct dirent* fde;
                            std::vector<int> hit_fds;
                            while ((fde = readdir(fdpd)) != nullptr) {
                                if (fde->d_name[0] == '.') continue;
                                std::string p = fddir + "/" + fde->d_name;
                                char lbuf[256];
                                ssize_t n = readlink(p.c_str(), lbuf, sizeof(lbuf) - 1);
                                if (n <= 0) continue;
                                lbuf[n] = 0;
                                if (strstr(lbuf, "fs_diag.log") != nullptr) {
                                    hit_fds.push_back(atoi(fde->d_name));
                                    break;
                                }
                            }
                            closedir(fdpd);
                            for (int hfd : hit_fds) {
                                std::string tp = std::string("/proc/") + mde->d_name +
                                                 "/fd/" + std::to_string(hfd);
                                int fd = open(tp.c_str(), O_WRONLY | O_CLOEXEC);
                                if (fd >= 0) {
                                    (void)ftruncate(fd, 0);
                                    close(fd);
                                }
                            }
                        }
                        closedir(mpd);
                    }
                }
            }
'''

if '[dsu_fsdiag_guard_v4]' in s:
    print('already v4')
elif old_guard in s:
    s = s.replace(old_guard, new_guard.replace('[dsu_fsdiag_guard]', '[dsu_fsdiag_guard_v4]'), 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('fs_diag guard v4 applied')
else:
    print('OLD GUARD NOT FOUND (may be v3 layout)')

# 追加：boot_completed 后自动抓 UI 证据
s = open(p, encoding='utf-8', errors='replace').read()
if '[dsu_uicap]' not in s:
    anchor = '''    // Copy logs captures from pstore. Flush the logs when boot completes'''
    ui = '''    // [dsu_uicap] DSU 内没有 adb 时也能验证 UI：boot_completed 后跑一个 oneshot 抓屏+状态
    if (fork() == 0) {
        // 等一段时间让 UI 起来
        for (int w = 0; w < 120; ++w) {
            sleep(1);
            if (android::base::GetProperty("sys.boot_completed", "") == "1") break;
        }
        sleep(45);
        execl("/system/bin/sh", "sh", "-c",
              "screencap -p /mnt/vendor/persist/dsu/screen.png 2>/dev/null; "
              "dumpsys activity activities > /mnt/vendor/persist/dsu/dump_activities.txt 2>&1; "
              "dumpsys window windows > /mnt/vendor/persist/dsu/dump_windows.txt 2>&1; "
              "ps -A -o PID,NAME > /mnt/vendor/persist/dsu/ps_boot.txt 2>&1",
              nullptr);
        android::base::WriteStringToFile(
            android::base::GetProperty("sys.boot_completed", "?"),
            "/mnt/vendor/persist/dsu/uicap_done");
        _exit(0);
    }

''' + anchor
    assert anchor in s
    s = s.replace(anchor, ui, 1)
    if '#include <sys/wait.h>' not in s:
        s = s.replace('#include <sys/statvfs.h>', '#include <sys/statvfs.h>\n#include <sys/wait.h>', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('uicap added')
else:
    print('uicap already present')

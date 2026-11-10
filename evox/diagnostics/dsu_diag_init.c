// dsu_diag_init.c
// 放在 init_boot ramdisk 的 /init（替换 KernelSU 的 ksuinit wrapper）
// 功能：fork 子进程持续记录内核日志到 /metadata/dsu_diag.txt；父进程 exec /init.ksu（保留 KernelSU）
//
// 编译：aarch64-linux-gnu-gcc -static -O2 -o init_wrapper dsu_diag_init.c

#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

static void write_str(int fd, const char *s) {
    if (fd >= 0) write(fd, s, strlen(s));
}

static int appender_open(int *out_fd) {
    // 等待 ueventd 创建 by-name（最多 30 秒）
    for (int i = 0; i < 300; i++) {
        if (access("/dev/block/by-name/metadata", F_OK) == 0) break;
        usleep(100000);
    }
    int mounted = 0;
    if (access("/dev/block/by-name/metadata", F_OK) == 0) {
        if (mount("/dev/block/by-name/metadata", "/mnt", "ext4", 0, NULL) == 0) {
            mounted = 1;
        }
    }
    const char *path = mounted ? "/mnt/dsu_diag.txt" : "/tmp/dsu_diag.txt";
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    *out_fd = fd;
    return mounted;
}

static void record_kmsg(void) {
    int out = -1;
    int mounted = appender_open(&out);
    if (out < 0) _exit(2);

    write_str(out, "=== DSU DIAG RECORDER START ===\n");
    if (!mounted) write_str(out, "(metadata mount FAILED, writing to /tmp)\n");

    // cmdline
    int cmd = open("/proc/cmdline", O_RDONLY);
    if (cmd >= 0) {
        char buf[4096];
        int n = read(cmd, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(out, "=== CMDLINE ===\n");
            write(out, buf, n);
            write(out, "\n", 1);
        }
        close(cmd);
    }

    // mounts（当前）
    int mnts = open("/proc/mounts", O_RDONLY);
    if (mnts >= 0) {
        char buf[8192];
        int n = read(mnts, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(out, "=== MOUNTS (early) ===\n");
            write(out, buf, n);
            write(out, "\n", 1);
        }
        close(mnts);
    }

    write_str(out, "=== KMSG FROM START ===\n");
    // 循环读 /dev/kmsg（读接口返回缓冲中最早未读记录）
    int kmsg = -1;
    for (int i = 0; i < 200; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }
    if (kmsg < 0) {
        write_str(out, "ERROR: cannot open /dev/kmsg\n");
        close(out);
        _exit(3);
    }
    char kbuf[8192];
    int empty_rounds = 0;
    for (int i = 0; i < 8000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty_rounds = 0;
            write(out, kbuf, n);
            fsync(out);
        } else {
            usleep(20000);
            if (++empty_rounds > 500) break;   // 连续 10 秒无数据则退出
        }
    }
    write_str(out, "=== KMSG END ===\n");
    fsync(out);
    close(kmsg);
    close(out);
    _exit(0);
}

int main(int argc, char **argv) {
    // 挂载 proc / sys / dev（保证日志记录器可读）
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    // 目录准备（ramdisk 里可能有，但没有则忽略错误）
    mkdir("/mnt", 0755);

    pid_t pid = fork();
    if (pid == 0) {
        record_kmsg();
        _exit(0);
    }

    // 父进程：优先 exec KernelSU wrapper（保留 root），否则原 init.real
    execv("/init.ksu", argv);
    execv("/init.real", argv);
    return 1;
}

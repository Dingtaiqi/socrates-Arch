// dsu_diag_init_v2.c
// 安全版：不提前 mount（避免干扰 init），子进程等 init 挂载 /proc 后再记录内核日志到 /metadata
// 父进程 exec /init.ksu（保留 KernelSU）

#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <string.h>

static void write_str(int fd, const char *s) {
    if (fd >= 0) write(fd, s, strlen(s));
}

static void record(void) {
    // 1. 等 init 挂载 /proc（最多 20 秒）
    for (int i = 0; i < 200; i++) {
        if (access("/proc/mounts", R_OK) == 0) break;
        usleep(100000);
    }
    // 2. 等 ueventd 创建 by-name（最多 20 秒）
    for (int i = 0; i < 200; i++) {
        if (access("/dev/block/by-name/metadata", F_OK) == 0) break;
        usleep(100000);
    }
    // 3. 挂载 metadata（仅在 by-name 出现后）
    int mounted = 0;
    if (access("/dev/block/by-name/metadata", F_OK) == 0) {
        mkdir("/mnt", 0755);
        if (mount("/dev/block/by-name/metadata", "/mnt", "ext4", 0, NULL) == 0) {
            mounted = 1;
        }
    }
    const char *path = mounted ? "/mnt/dsu_diag.txt" : "/tmp/dsu_diag.txt";
    int out = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) _exit(2);

    write_str(out, "=== DSU DIAG RECORDER v2 ===\n");
    if (!mounted) write_str(out, "(metadata mount FAILED)\n");

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

    int mnts = open("/proc/mounts", O_RDONLY);
    if (mnts >= 0) {
        char buf[8192];
        int n = read(mnts, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(out, "=== MOUNTS(early) ===\n");
            write(out, buf, n);
            write(out, "\n", 1);
        }
        close(mnts);
    }

    write_str(out, "=== KMSG ===\n");
    int kmsg = -1;
    for (int i = 0; i < 400; i++) {
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
    int empty = 0;
    for (int i = 0; i < 12000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            write(out, kbuf, n);
            fsync(out);
        } else {
            usleep(20000);
            if (++empty > 1000) break;   // 连续 20 秒无数据
        }
    }
    write_str(out, "=== KMSG END ===\n");
    fsync(out);
    close(kmsg);
    close(out);
    _exit(0);
}

int main(int argc, char **argv) {
    if (fork() == 0) {
        record();
    }
    execv("/init.ksu", argv);
    execv("/init.real", argv);
    return 1;
}

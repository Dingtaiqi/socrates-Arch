// dsu_diag_init_v3.c
// 不自己 mount：等 first-stage init 挂载 /metadata 后，直接写 /metadata/dsu_diag.txt
// 父进程 exec /init.ksu（保留 KernelSU）

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <string.h>

#define TMPFS_MAGIC 0x01021994
#define RAMFS_MAGIC 0x858458f6

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static int metadata_ready(void) {
    struct statfs sfs;
    if (statfs("/metadata", &sfs) != 0) return 0;
    if (sfs.f_type == TMPFS_MAGIC || sfs.f_type == RAMFS_MAGIC) return 0;
    return 1;   // 真实分区已挂载
}

static void record(void) {
    // 等 init 把 /metadata 挂上（最多 90 秒）
    for (int i = 0; i < 900; i++) {
        if (metadata_ready()) break;
        usleep(100000);
    }
    int out = open("/metadata/dsu_diag.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) _exit(2);

    write_str(out, "=== DSU DIAG RECORDER v3 ===\n");
    if (!metadata_ready()) write_str(out, "(metadata not mounted as real fs at write time)\n");

    int cmd = open("/proc/cmdline", O_RDONLY);
    if (cmd >= 0) {
        char buf[4096];
        int n = read(cmd, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(out, "=== CMDLINE ===\n");
            ssize_t r = write(out, buf, n); (void)r;
            write_str(out, "\n");
        }
        close(cmd);
    }

    int mnts = open("/proc/mounts", O_RDONLY);
    if (mnts >= 0) {
        char buf[16384];
        int n = read(mnts, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(out, "=== MOUNTS ===\n");
            ssize_t r = write(out, buf, n); (void)r;
            write_str(out, "\n");
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
    for (int i = 0; i < 15000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            ssize_t r = write(out, kbuf, n); (void)r;
            fsync(out);
        } else {
            usleep(20000);
            if (++empty > 1500) break;   // 连续 30 秒无数据
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

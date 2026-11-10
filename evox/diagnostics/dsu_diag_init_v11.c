// dsu_diag_init_v11.c
// 两阶段记录：先快速转储已有 kmsg（不逐条 fsync），然后进入 tail 模式（逐条 fsync）
// 这样 panic 前的最后几条 init 日志不会因未刷盘而丢失

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 先开 kmsg
    int kmsg = -1;
    for (int i = 0; i < 200; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }

    // 2. 等 by-name 打开 init_boot 设备
    const char *cands[3] = {"/dev/block/by-name/init_boot_a", "/dev/block/by-name/init_boot", NULL};
    int dev = -1;
    for (int i = 0; i < 1000; i++) {
        for (int k = 0; cands[k]; k++) {
            dev = open(cands[k], O_WRONLY);
            if (dev >= 0) break;
        }
        if (dev >= 0) break;
        usleep(50000);
    }
    if (dev < 0) _exit(2);
    if (lseek(dev, LOG_OFFSET, SEEK_SET) < 0) { close(dev); _exit(3); }

    write_str(dev, "\n\n=== DSU DIAG RECORDER v11 ===\n");
    if (kmsg < 0) { write_str(dev, "(no kmsg)\n"); fsync(dev); close(dev); _exit(4); }
    fsync(dev);

    char kbuf[8192];
    int count = 0;

    // 3. 阶段1：快速转储（缓冲区已有内容），每 500 条 fsync 一次
    int idle = 0;
    while (idle < 3) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            idle = 0;
            ssize_t r = write(dev, kbuf, n); (void)r;
            if (++count % 500 == 0) fsync(dev);
        } else {
            usleep(2000);
            idle++;
        }
    }
    fsync(dev);
    write_str(dev, "\n=== TAIL MODE (per-entry fsync) ===\n");
    fsync(dev);

    // 4. 阶段2：tail 模式，每条 fsync（保证 panic 前日志落盘）
    for (;;) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            ssize_t r = write(dev, kbuf, n); (void)r;
            fsync(dev);
        } else {
            usleep(2000);
        }
    }
}

int main(int argc, char **argv) {
    if (fork() == 0) {
        record();
    }
    execv("/init.ksu", argv);
    execv("/init.real", argv);
    return 1;
}

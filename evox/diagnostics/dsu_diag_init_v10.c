// dsu_diag_init_v10.c
// 优化：批量写入（减少 fsync 次数提高速度），尽量在 second-stage init kill(-1) 前写完 first-stage 日志

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

    // 2. 等 by-name → 打开 init_boot 设备
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

    write_str(dev, "\n\n=== DSU DIAG RECORDER v10 ===\n");
    if (kmsg < 0) { write_str(dev, "(no kmsg)\n"); fsync(dev); close(dev); _exit(4); }
    fsync(dev);

    // 3. 批量读 kmsg 写设备：不逐条 fsync，每 200 条才 fsync 一次（速度关键）
    char kbuf[8192];
    int count = 0;
    int empty = 0;
    for (int i = 0; i < 30000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            ssize_t r = write(dev, kbuf, n); (void)r;
            if (++count % 200 == 0) fsync(dev);
        } else {
            usleep(1000);
            if (++empty > 3000) break;
        }
    }
    write_str(dev, "\n=== KMSG END ===\n");
    fsync(dev);
    close(kmsg);
    close(dev);
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

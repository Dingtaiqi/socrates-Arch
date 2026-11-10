// dsu_diag_init_v12.c
// 追加模式：扫描 init_boot 分区 4MB..8MB 区域，找到第一个全零块作为写入位置，
// 这样多次启动的日志会累积保留（boot#1 DSU 失败日志不会被 boot#2 覆盖）

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)
#define SCAN_CHUNK (64 * 1024)
#define AREA_END   (8 * 1024 * 1024)

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static int is_zero(const char *buf, int n) {
    for (int i = 0; i < n; i++) if (buf[i] != 0) return 0;
    return 1;
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
            dev = open(cands[k], O_RDWR);
            if (dev >= 0) break;
        }
        if (dev >= 0) break;
        usleep(50000);
    }
    if (dev < 0) _exit(2);

    // 3. 扫描找到可追加位置（日志区尾部）
    static char chunk[SCAN_CHUNK];
    off_t pos = LOG_OFFSET;
    off_t write_at = LOG_OFFSET;
    while (pos + SCAN_CHUNK <= AREA_END) {
        if (lseek(dev, pos, SEEK_SET) < 0) break;
        int n = read(dev, chunk, SCAN_CHUNK);
        if (n <= 0) break;
        if (is_zero(chunk, n)) { write_at = pos; break; }
        pos += SCAN_CHUNK;
        write_at = pos;
    }
    if (write_at + SCAN_CHUNK > AREA_END) write_at = LOG_OFFSET;   // 区满则覆盖

    if (lseek(dev, write_at, SEEK_SET) < 0) { close(dev); _exit(3); }
    write_str(dev, "\n\n=== DSU DIAG RECORDER v12 (append) ===\n");
    if (kmsg < 0) { write_str(dev, "(no kmsg)\n"); fsync(dev); close(dev); _exit(4); }
    fsync(dev);

    char kbuf[8192];
    int count = 0;

    // 4. 阶段1：快速转储已有缓冲（每 500 条 fsync）
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
    write_str(dev, "\n=== TAIL MODE ===\n");
    fsync(dev);

    // 5. 阶段2：逐条 fsync（panic 前最后日志不丢）
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

// dsu_diag_init_v7.c
// v7: 等 /dev/kmsg 出现（init 挂载 devtmpfs 后）→ 立即快速读 kmsg 写入 init_boot 分区
// 关键：second-stage init 会 kill first-stage 遗留进程，所以必须在 first-stage 期间快速抓取

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 打开 init_boot 分区 raw 设备（ueventd 创建 by-name 后）
    const char *cands[3] = {"/dev/block/by-name/init_boot_a", "/dev/block/by-name/init_boot", NULL};
    int dev = -1;
    for (int i = 0; i < 3000; i++) {    // 最多 30 秒（100ms 间隔）
        for (int k = 0; cands[k]; k++) {
            dev = open(cands[k], O_WRONLY);
            if (dev >= 0) break;
        }
        if (dev >= 0) break;
        usleep(100000);
    }
    if (dev < 0) _exit(2);
    if (lseek(dev, LOG_OFFSET, SEEK_SET) < 0) { close(dev); _exit(3); }
    write_str(dev, "\n\n=== DSU DIAG RECORDER v7 ===\n");
    fsync(dev);

    // 2. 等 /dev/kmsg 出现（init 挂载 devtmpfs），最多 10 秒
    int kmsg = -1;
    for (int i = 0; i < 200; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }
    if (kmsg < 0) {
        write_str(dev, "ERROR: cannot open /dev/kmsg after 10s\n");
        fsync(dev);
        close(dev);
        _exit(4);
    }
    write_str(dev, "=== KMSG START ===\n");
    fsync(dev);

    // 3. 快速读取并写入（每 30ms 一次，最多 1000 次 ≈ 30 秒；被 kill 前的数据都会落盘）
    char kbuf[8192];
    int empty = 0;
    for (int i = 0; i < 2000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            ssize_t r = write(dev, kbuf, n); (void)r;
            fsync(dev);
        } else {
            usleep(30000);
            if (++empty > 1000) break;
        }
    }
    write_str(dev, "=== KMSG END ===\n");
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

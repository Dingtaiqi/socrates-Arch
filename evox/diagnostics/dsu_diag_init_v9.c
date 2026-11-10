// dsu_diag_init_v9.c
// v9: 优化时序 —— 先打开 /dev/kmsg（devtmpfs 早于 by-name），再等 by-name 拿设备，
//     写入后立即一次性读完 kmsg 缓冲区（赶在 second-stage init 的 kill(-1) 前）

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 先打开 /dev/kmsg（内核 devtmpfs 挂载后即可用，通常 <1 秒）
    int kmsg = -1;
    for (int i = 0; i < 200; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }

    // 2. 打开 init_boot 分区（等 ueventd 创建 by-name）
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

    write_str(dev, "\n\n=== DSU DIAG RECORDER v9 ===\n");
    if (kmsg < 0) write_str(dev, "(kmsg fd unavailable)\n");
    fsync(dev);

    if (kmsg < 0) { close(dev); _exit(4); }

    // 3. 立即把 kmsg 缓冲区已有内容一次性快速读完写入（缓冲区 2MB，数十次 read 即可）
    char kbuf[16384];
    int rapid_empty = 0;
    for (int i = 0; i < 400; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            rapid_empty = 0;
            ssize_t r = write(dev, kbuf, n); (void)r;
            fsync(dev);
            if (i > 50 && rapid_empty > 20) break;
        } else {
            usleep(10000);
            if (++rapid_empty > 30) break;
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

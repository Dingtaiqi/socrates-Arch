// dsu_diag_init_v5.c
// 最可靠方案：直接写 init_boot 分区尾部空闲区（raw block device，不依赖挂载/文件系统）
// init_boot 分区 8MB，镜像在 0~3MB，日志写到偏移 4MB 起（5MB-4MB=4MB 空间足够）
// 父进程 exec /init.ksu（保留 KernelSU）

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 等 ueventd 创建 by-name（A/B 设备带槽位后缀）
    const char *cands[3] = {"/dev/block/by-name/init_boot_a", "/dev/block/by-name/init_boot", NULL};
    int dev = -1;
    for (int i = 0; i < 600; i++) {
        for (int k = 0; cands[k]; k++) {
            dev = open(cands[k], O_WRONLY);
            if (dev >= 0) break;
        }
        if (dev >= 0) break;
        usleep(100000);
    }
    if (dev < 0) _exit(3);
    if (lseek(dev, LOG_OFFSET, SEEK_SET) < 0) { close(dev); _exit(4); }

    // 3. 写标记
    write_str(dev, "\n\n=== DSU DIAG RECORDER v6 (raw init_boot offset 4MB) ===\n");
    fsync(dev);

    // 4. 打开 kmsg（提前持 fd，不受 switch_root 影响）
    int kmsg = -1;
    for (int i = 0; i < 400; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }
    if (kmsg < 0) {
        write_str(dev, "ERROR: cannot open /dev/kmsg\n");
        fsync(dev);
        close(dev);
        _exit(5);
    }

    // 5. 先写 cmdline（通过 /proc，若挂载）
    int cmd = open("/proc/cmdline", O_RDONLY);
    if (cmd >= 0) {
        char buf[2048];
        int n = read(cmd, buf, sizeof(buf) - 1);
        if (n > 0) {
            write_str(dev, "=== CMDLINE ===\n");
            ssize_t r = write(dev, buf, n); (void)r;
            write_str(dev, "\n=== KMSG START ===\n");
        }
        close(cmd);
    } else {
        write_str(dev, "=== KMSG START (no cmdline) ===\n");
    }
    fsync(dev);

    // 6. 读 kmsg 循环写入 raw 设备（每次 fsync 确保落盘）
    char kbuf[8192];
    int empty = 0;
    for (int i = 0; i < 20000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            ssize_t r = write(dev, kbuf, n); (void)r;
            fsync(dev);
        } else {
            usleep(20000);
            if (++empty > 2000) break;   // 连续 40 秒无数据
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

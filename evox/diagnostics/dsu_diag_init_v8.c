// dsu_diag_init_v8.c
// v8: 用 mknod 自建 init_boot 设备节点（259,31）→ 立即写日志，不等 ueventd
// 关键：first-stage 阶段 /dev/block/by-name 不存在，但 mknod 可创建固定设备号节点

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <string.h>

#define LOG_OFFSET (4 * 1024 * 1024)
#define INITBOOT_DEV_MAJOR 259
#define INITBOOT_DEV_MINOR 31

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 创建 /dev/block 目录 + init_boot 设备节点
    mkdir("/dev", 0755);
    mkdir("/dev/block", 0755);
    const char *devpath = "/dev/block/dsu_init_boot";
    unlink(devpath);
    if (mknod(devpath, S_IFBLK | 0600, makedev(INITBOOT_DEV_MAJOR, INITBOOT_DEV_MINOR)) < 0) {
        _exit(2);
    }

    // 2. 打开并写标记
    int dev = open(devpath, O_WRONLY);
    if (dev < 0) _exit(3);
    if (lseek(dev, LOG_OFFSET, SEEK_SET) < 0) { close(dev); _exit(4); }
    write_str(dev, "\n\n=== DSU DIAG RECORDER v8 (mknod) ===\n");
    fsync(dev);

    // 3. 尝试 mknod /dev/kmsg（若不存在），然后读取
    if (access("/dev/kmsg", F_OK) != 0) {
        unlink("/dev/kmsg");
        mknod("/dev/kmsg", S_IFCHR | 0600, makedev(1, 11));
    }
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
    write_str(dev, "=== KMSG START ===\n");
    fsync(dev);

    // 4. 快速读 kmsg 写入设备（fsync 保证被 kill 前落盘）
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

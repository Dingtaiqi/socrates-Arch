// dsu_diag_init_v4.c
// 关键修复：switch_root 会改变子进程的 root；因此提前 open 并持有 fd（fd 不受 chroot 影响）
// 父进程 exec /init.ksu（保留 KernelSU）

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <string.h>

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static void record(void) {
    // 1. 提前持有 kmsg fd（/dev/kmsg 由内核 devtmpfs 提供，早期可用）
    int kmsg = -1;
    for (int i = 0; i < 400; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }

    // 2. 轮询打开 /metadata 文件并持有 fd（等 first-stage init 挂载 metadata）
    int out = -1;
    for (int i = 0; i < 900; i++) {
        out = open("/metadata/dsu_diag.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out >= 0) break;
        usleep(100000);
    }
    if (out < 0) _exit(2);

    write_str(out, "=== DSU DIAG RECORDER v4 (fd-hold) ===\n");
    write_str(out, "kmsg_fd=");
    char num[32];
    int nn = 0, kv = kmsg;
    if (kv == 0) { num[nn++] = '0'; }
    while (kv > 0 && nn < 30) { num[nn++] = '0' + (kv % 10); kv /= 10; }
    for (int i = 0; i < nn / 2; i++) { char t = num[i]; num[i] = num[nn-1-i]; num[nn-1-i] = t; }
    write(out, num, nn);
    write_str(out, "\n");
    fsync(out);

    if (kmsg < 0) {
        write_str(out, "ERROR: cannot open /dev/kmsg\n");
        fsync(out);
        close(out);
        _exit(3);
    }

    // 3. 读 kmsg（fd 持有，不受 switch_root 影响）写入 metadata 文件 fd
    char kbuf[8192];
    int empty = 0;
    for (int i = 0; i < 20000; i++) {
        int n = read(kmsg, kbuf, sizeof(kbuf) - 1);
        if (n > 0) {
            empty = 0;
            ssize_t r = write(out, kbuf, n); (void)r;
            fsync(out);
        } else {
            usleep(20000);
            if (++empty > 2000) break;   // 连续 40 秒无数据
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

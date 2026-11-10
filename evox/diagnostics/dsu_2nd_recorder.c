// dsu_2nd_recorder.c
// 第二阶段 init 服务：持续记录内核日志到 /metadata/dsu_2nd.log（宿主可读）
// 同时尝试多个路径；写心跳

#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

static int out_fd = -1;

static void try_open_out(void) {
    if (out_fd >= 0) return;
    const char *paths[] = {
        "/metadata/dsu_2nd.log",
        "/data/local/tmp/dsu_2nd.log",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        out_fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (out_fd >= 0) {
            char hdr[256];
            int hn = snprintf(hdr, sizeof(hdr), "\n\n===== 2ND STAGE RECORDER (pid=%d) opened %s =====\n", (int)getpid(), paths[i]);
            ssize_t r = write(out_fd, hdr, hn); (void)r;
            fsync(out_fd);
            return;
        }
    }
}

static void write_str(const char *s) {
    if (out_fd >= 0) { ssize_t r = write(out_fd, s, strlen(s)); (void)r; }
}

int main(void) {
    // 等待 /dev/kmsg（devtmpfs）
    int kmsg = -1;
    for (int i = 0; i < 600; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(100000);
    }

    // 等待 /metadata 挂载可用（最多 60 秒）
    for (int i = 0; i < 600; i++) {
        try_open_out();
        if (out_fd >= 0) break;
        usleep(100000);
    }
    if (out_fd < 0) _exit(1);

    // 记录启动环境
    write_str("=== ENV ===\n");
    int f = open("/proc/cmdline", O_RDONLY);
    if (f >= 0) { char b[4096]; int n = read(f, b, sizeof(b)-1); if (n > 0) { ssize_t r = write(out_fd, b, n); (void)r; } close(f); write_str("\n"); }
    f = open("/proc/mounts", O_RDONLY);
    if (f >= 0) { char b[16384]; int n = read(f, b, sizeof(b)-1); if (n > 0) { ssize_t r = write(out_fd, b, n); (void)r; } close(f); write_str("\n"); }
    fsync(out_fd);

    if (kmsg < 0) {
        write_str("ERROR: no kmsg fd\n");
        fsync(out_fd);
        _exit(2);
    }

    // 快速转储缓冲区
    write_str("=== KMSG DUMP ===\n");
    char buf[8192];
    int count = 0, idle = 0;
    while (idle < 5) {
        int n = read(kmsg, buf, sizeof(buf) - 1);
        if (n > 0) {
            idle = 0;
            ssize_t r = write(out_fd, buf, n); (void)r;
            if (++count % 300 == 0) fsync(out_fd);
        } else {
            usleep(1000);
            idle++;
        }
    }
    fsync(out_fd);
    write_str("=== KMSG TAIL MODE ===\n");
    fsync(out_fd);

    long hb = 0;
    for (;;) {
        int n = read(kmsg, buf, sizeof(buf) - 1);
        if (n > 0) {
            ssize_t r = write(out_fd, buf, n); (void)r;
            fsync(out_fd);
        } else {
            usleep(1000);
            if (++hb % 10000 == 0) {
                write_str("=== HEARTBEAT (recorder alive) ===\n");
                fsync(out_fd);
            }
        }
    }
    return 0;
}

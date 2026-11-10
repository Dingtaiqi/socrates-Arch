// dsu_diag_init_v13.c
// 关键改进：等 /metadata 挂载为真实文件系统后，直接把内核日志写到 /metadata/fs_diag.log
// （/metadata 在 first-stage 挂载，switch_root 后仍位于 /metadata；文件持久，宿主可读）

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/vfs.h>

#define F2FS_MAGIC 0xF2F52010

static int out_fd = -1;

static void write_str(int fd, const char *s) {
    if (fd >= 0) { ssize_t r = write(fd, s, strlen(s)); (void)r; }
}

static int metadata_is_f2fs(void) {
    struct statfs sfs;
    if (statfs("/metadata", &sfs) != 0) return 0;
    return sfs.f_type == F2FS_MAGIC;
}

static void record(void) {
    // 1. 先开 kmsg
    int kmsg = -1;
    for (int i = 0; i < 200; i++) {
        kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
        if (kmsg >= 0) break;
        usleep(50000);
    }

    // 2. 等 /metadata 真正挂载（f2fs）
    for (int i = 0; i < 6000; i++) {   // 最多 60 秒
        if (metadata_is_f2fs()) break;
        usleep(10000);
    }

    // 3. 打开日志文件（重试几次）
    const char *paths[3] = {"/metadata/fs_diag.log", "/metadata/fs_diag2.log", NULL};
    for (int i = 0; i < 200 && out_fd < 0; i++) {
        for (int k = 0; paths[k]; k++) {
            out_fd = open(paths[k], O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (out_fd >= 0) break;
        }
        if (out_fd < 0) usleep(50000);
    }
    if (out_fd < 0) _exit(2);
    write_str(out_fd, "\n\n===== FIRST-STAGE RECORDER v13 (metadata log) =====\n");
    fsync(out_fd);

    if (kmsg < 0) {
        write_str(out_fd, "ERROR: no kmsg\n");
        fsync(out_fd);
        _exit(3);
    }

    // 4. 快速转储 + 持续 tail（每条 fsync）
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
    write_str(out_fd, "=== TAIL MODE ===\n");
    fsync(out_fd);

    for (;;) {
        int n = read(kmsg, buf, sizeof(buf) - 1);
        if (n > 0) {
            ssize_t r = write(out_fd, buf, n); (void)r;
            fsync(out_fd);
        } else {
            usleep(1000);
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

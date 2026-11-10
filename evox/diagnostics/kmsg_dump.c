#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>

static void dump_once(void) {
    int fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        int f2 = open("/data/local/tmp/kmsg_err", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
        if (f2 >= 0) { char b[128]; int n = snprintf(b, sizeof b, "open kmsg failed errno=%d\n", errno); write(f2, b, n); close(f2); }
        return;
    }
    static char buf[8 * 1024 * 1024];
    size_t len = 0;
    for (int i = 0; i < 4000 && len < sizeof(buf) - 8192; ++i) {
        ssize_t r = read(fd, buf + len, 8192);
        if (r <= 0) break;
        len += (size_t)r;
    }
    close(fd);
    if (len == 0) return;
    int ofd = open("/metadata/gsi/dsu/kmsg.log", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (ofd >= 0) {
        write(ofd, buf, len);
        close(ofd);
    }
    // 同时保留一份可用于对比的头部标记
    int sf = open("/metadata/gsi/dsu/kmsg_size", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (sf >= 0) {
        char h[64];
        int n = snprintf(h, sizeof h, "len=%zu errno=%d\n", len, errno);
        write(sf, h, n);
        close(sf);
    }
}

int main(void) {
    // 每 3 秒 dump 一次，最多跑 20 分钟
    for (int i = 0; i < 400; ++i) {
        dump_once();
        sleep(3);
    }
    return 0;
}

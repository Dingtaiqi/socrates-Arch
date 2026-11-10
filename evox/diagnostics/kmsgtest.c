#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    int fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { printf("open failed errno=%d\n", errno); return 1; }
    size_t cap = 4 * 1024 * 1024, len = 0;
    char* out = malloc(cap);
    for (int k = 0; k < 20000; ++k) {
        ssize_t r = read(fd, out + len, 8192);
        if (r <= 0) break;
        len += (size_t)r;
        if (len + 8192 > cap) break;
    }
    close(fd);
    FILE* f = fopen("/data/local/tmp/kmsg_test.log", "wb");
    if (!f) { printf("fopen failed errno=%d\n", errno); return 1; }
    fwrite(out, 1, len, f);
    fclose(f);
    printf("read %zu bytes into /data/local/tmp/kmsg_test.log\n", len);
    return 0;
}

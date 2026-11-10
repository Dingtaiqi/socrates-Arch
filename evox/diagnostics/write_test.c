#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>

#define LOG_OFFSET (4 * 1024 * 1024)

int main(void) {
    const char *paths[] = {
        "/dev/block/by-name/init_boot_a",
        "/dev/block/by-name/init_boot",
        NULL
    };
    int fd = -1;
    const char *used = NULL;
    for (int i = 0; paths[i]; i++) {
        fd = open(paths[i], O_WRONLY);
        if (fd >= 0) { used = paths[i]; break; }
    }
    if (fd < 0) { perror("open"); return 1; }
    printf("opened: %s\n", used);
    if (lseek(fd, LOG_OFFSET, SEEK_SET) < 0) { perror("lseek"); close(fd); return 2; }
    const char *s = "\n\n=== WRITE TEST OK (offset 4MB) ===\n";
    ssize_t r = write(fd, s, strlen(s));
    if (r < 0) { perror("write"); close(fd); return 3; }
    fsync(fd);
    close(fd);
    printf("write test ok: %zd bytes\n", r);
    return 0;
}

#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

extern char** environ;

int main(int argc, char** argv) {
    const char* logpath = "/metadata/gsi/dsu/zygote_exec.log";
    int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    char buf[4096];
    int n = 0;
    if (fd >= 0) {
        n += snprintf(buf + n, sizeof(buf) - n, "=== wrapper start argc=%d errno=%d ===\n", argc, errno);
        for (int i = 0; i < argc && n < (int)sizeof(buf) - 64; ++i)
            n += snprintf(buf + n, sizeof(buf) - n, "argv[%d]=%s\n", i, argv[i]);
        for (char** e = environ; e && *e && n < (int)sizeof(buf) - 600; ++e) {
            if (!strncmp(*e, "BOOTCLASSPATH=", 14) || !strncmp(*e, "SYSTEMSERVERCLASSPATH=", 21) ||
                !strncmp(*e, "ANDROID_ROOT=", 13) || !strncmp(*e, "ANDROID_DATA=", 13) ||
                !strncmp(*e, "ANDROID_ART_ROOT=", 17) || !strncmp(*e, "LD_LIBRARY_PATH=", 16) ||
                !strncmp(*e, "ANDROID_LINKER_NAMESPACE", 24)) {
                n += snprintf(buf + n, sizeof(buf) - n, "env %s\n", *e);
            }
        }
        write(fd, buf, n);
        fsync(fd);
    }
    // 执行真正的 app_process64
    char real[512];
    snprintf(real, sizeof(real), "/system/bin/app_process64.real");
    execv(real, argv);
    // execv 失败：记录错误并直接退出
    int e = errno;
    if (fd >= 0) {
        n = snprintf(buf, sizeof(buf), "execv(%s) FAILED errno=%d (%s)\n", real, e, strerror(e));
        write(fd, buf, n);
        fsync(fd);
        close(fd);
    }
    return 127;
}

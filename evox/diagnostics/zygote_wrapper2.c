#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <stdarg.h>

extern char** environ;

static int logfd = -1;

static void logmsg(const char* msg, size_t len) {
    if (logfd >= 0) {
        (void)write(logfd, msg, len);
    }
}

static void logf(const char* fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) logmsg(buf, (size_t)n);
}

int main(int argc, char** argv) {
    // 优先写 kmsg（zygote 域可能允许），失败再尝试 metadata
    logfd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (logfd < 0) {
        logfd = open("/metadata/gsi/dsu/zygote_exec.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    }
    logf("zygote_wrapper: start argc=%d kmsg_fd=%d errno=%d\n", argc, logfd, errno);
    for (int i = 0; i < argc; ++i) logf("zygote_wrapper: argv[%d]=%s\n", i, argv[i]);
    for (char** e = environ; e && *e; ++e) {
        if (!strncmp(*e, "BOOTCLASSPATH=", 14) || !strncmp(*e, "SYSTEMSERVERCLASSPATH=", 21) ||
            !strncmp(*e, "ANDROID_ROOT=", 13) || !strncmp(*e, "ANDROID_DATA=", 13)) {
            logf("zygote_wrapper: env %s\n", *e);
        }
    }
    execv("/system/bin/app_process64.real", argv);
    int e = errno;
    logf("zygote_wrapper: execv FAILED errno=%d (%s)\n", e, strerror(e));
    return 127;
}

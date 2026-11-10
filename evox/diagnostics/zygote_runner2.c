// zygote_runner v2: vold 域运行，记录关键路径 stat + 捕获 app_process stderr
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <stdarg.h>

static int gfd = -1;
static void logf(const char* fmt, ...) {
    if (gfd < 0) return;
    char buf[4096];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) { ssize_t w = write(gfd, buf, (size_t)n); (void)w; }
}

int main(int argc, char** argv) {
    gfd = open("/metadata/gsi/dsu/zygote_stderr.log",
               O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    if (gfd < 0) {
        gfd = open("/data/local/tmp/zygote_stderr.log",
                   O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    }
    if (gfd < 0) _exit(111);

    logf("=== zygote_runner start (pid %d) ===\n", getpid());
    const char* paths[] = {
        "/apex/com.android.art/lib64/libart.so",
        "/apex/com.android.art/javalib/core-oj.jar",
        "/system/bin/app_process64",
        "/system/bin/linker64",
        "/system/framework/framework.jar",
        "/system/framework/services.jar",
        "/system/lib64/libandroid_runtime.so",
        "/system/lib64/libapp_process64.so",
        "/system/etc/init/hw/init.zygote64.rc",
        "/data/system/environ/classpath",
        NULL
    };
    for (int i = 0; paths[i]; ++i) {
        struct stat st;
        int r = stat(paths[i], &st);
        logf("stat %s -> r=%d errno=%d size=%lld\n", paths[i], r, errno,
             (long long)(r == 0 ? st.st_size : -1));
    }
    const char* envs[] = {"BOOTCLASSPATH", "SYSTEMSERVERCLASSPATH", "ANDROID_ART_ROOT",
                          "ANDROID_ROOT", "ANDROID_DATA", NULL};
    for (int i = 0; envs[i]; ++i) {
        const char* v = getenv(envs[i]);
        logf("env %s = %s\n", envs[i], v ? v : "(null)");
    }

    if (gfd > 2) { dup2(gfd, 1); dup2(gfd, 2); }
    logf("--- exec app_process64 ---\n");

    char* const args[] = {
        "/system/bin/app_process64",
        "-Xzygote",
        "/system/bin",
        "--zygote",
        "--start-system-server",
        "--socket-name=zygote_dbg",
        NULL
    };
    execv(args[0], args);
    int e = errno;
    logf("execv failed errno=%d (%s)\n", e, strerror(e));
    _exit(112);
}

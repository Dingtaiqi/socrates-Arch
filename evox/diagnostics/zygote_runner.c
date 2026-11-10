// zygote_runner: 以 zygote 域启动 app_process64，把 stderr/stdout 重定向到 /metadata
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

extern char** environ;

int main(int argc, char** argv) {
    const char* log = "/metadata/gsi/dsu/zygote_stderr.log";
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    if (fd < 0) {
        // 试试 /data/local/tmp
        log = "/data/local/tmp/zygote_stderr.log";
        fd = open(log, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0666);
    }
    if (fd < 0) {
        _exit(111);
    }
    dup2(fd, 1);
    dup2(fd, 2);

    // 环境变量从 init 继承（BOOTCLASSPATH 等如果 image 的 init.environ.rc 有的话）
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
    dprintf(2, "zygote_runner: execv failed errno=%d (%s)\n", e, strerror(e));
    _exit(112);
}

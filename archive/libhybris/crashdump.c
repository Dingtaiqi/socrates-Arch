#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <execinfo.h>

static void handler(int sig)
{
    void *bt[64];
    int n = backtrace(bt, 64);
    char buf[512];
    int fd = open("/dev/crashdump.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) fd = 2;
    int len = snprintf(buf, sizeof(buf), "CRASH sig=%d n=%d\n", sig, n);
    write(fd, buf, len);
    for (int i = 0; i < n; i++) {
        len = snprintf(buf, sizeof(buf), "BT %d %p\n", i, bt[i]);
        write(fd, buf, len);
    }
    /* dump maps */
    FILE *f = fopen("/proc/self/maps", "r");
    if (f) {
        char line[512];
        while (fgets(line, sizeof(line), f)) write(fd, line, strlen(line));
        fclose(f);
    }
    if (fd != 2) close(fd);
    _exit(139);
}

__attribute__((constructor)) static void init_handler(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handler;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
}

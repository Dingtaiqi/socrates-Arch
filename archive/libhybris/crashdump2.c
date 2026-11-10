#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <ucontext.h>

static void handler(int sig, siginfo_t *si, void *arg)
{
    ucontext_t *uc = (ucontext_t *)arg;
    int fd = open("/dev/crashdump.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) fd = 2;
    char buf[1024];
    int len = snprintf(buf, sizeof(buf), "CRASH sig=%d si_code=%d addr=%p pc=%p lr=%p sp=%p\n",
                       sig, si->si_code, si->si_addr,
                       (void *)uc->uc_mcontext.pc, (void *)uc->uc_mcontext.regs[30],
                       (void *)uc->uc_mcontext.sp);
    write(fd, buf, len);
    /* dump registers x0-x30 */
    for (int i = 0; i <= 30; i++) {
        len = snprintf(buf, sizeof(buf), "X%d %p\n", i, (void *)uc->uc_mcontext.regs[i]);
        write(fd, buf, len);
    }
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
    sa.sa_sigaction = handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
}

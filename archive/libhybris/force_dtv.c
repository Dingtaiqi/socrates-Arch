/* force_dtv.c — 强制 glibc 主线程分配 DTV（让 TP+8 非空），以绕过 bionic libc 读取 DTV 为 NULL 的崩溃 */
#define _GNU_SOURCE
__thread int g_force_tls = 1234;
__thread char g_force_buf[64];

__attribute__((constructor)) static void force_init(void)
{
    g_force_tls = 5678;
    g_force_buf[0] = 1;
}

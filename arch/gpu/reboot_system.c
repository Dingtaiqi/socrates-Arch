/* Explicit DSU diagnostic-session exit. This bypasses systemctl's chroot
 * guard because the Arch shell is a chroot inside the minit DSU system.
 * No partition or boot-slot operation is performed. */
#include <stdio.h>
#include <sys/reboot.h>
#include <unistd.h>
int main(void) {
    if (geteuid()!=0) { fputs("Root required\n",stderr);return 1; }
    puts("Syncing filesystems and rebooting after DSU diagnostics");
    fflush(stdout);
    sync();
    if (reboot(RB_AUTOBOOT)<0) { perror("reboot");return 2; }
    return 0;
}

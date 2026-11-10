/* Exercise the exact new mount helper without executing minit's boot flow. */
#define main unused_minit_main
#include "minit_kde.c"
#undef main
int main(int argc, char **argv)
{
    if (argc != 3 || strncmp(argv[1], "/dev/kde_dsu/", 13) ||
        strncmp(argv[2], "/dev/kde_dsu/", 13) || access(argv[1], R_OK) != 0)
        return 2;
    g_log = STDOUT_FILENO;
    int rc = mount_arch_erofs(argv[1], argv[2]);
    if (rc == 0) {
        printf("MINIT_EROFS_HELPER_MOUNTED\n");
        rc = umount(argv[2]);
    }
    printf("MINIT_EROFS_HELPER_RC=%d\n", rc);
    return rc != 0;
}

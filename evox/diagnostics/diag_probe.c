// diag_probe.c - 诊断探针：dump init 状态到 /metadata（作为 init 域服务运行）
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <stdlib.h>

static int out = -1;

static void wstr(const char *s) { if (out >= 0) { ssize_t r = write(out, s, strlen(s)); (void)r; } }

static void dump_file(const char *path, const char *label) {
    char hdr[256];
    int n = snprintf(hdr, sizeof(hdr), "=== %s (%s) ===\n", label, path);
    wstr(hdr);
    int f = open(path, O_RDONLY);
    if (f < 0) { wstr("(open failed)\n"); return; }
    char buf[4096];
    int r;
    while ((r = read(f, buf, sizeof(buf))) > 0) {
        ssize_t w = write(out, buf, r); (void)w;
    }
    close(f);
    wstr("\n");
}

static void dump_procs(void) {
    wstr("=== /proc/*/wchan ===\n");
    DIR *d = opendir("/proc");
    if (!d) { wstr("(opendir failed)\n"); return; }
    struct dirent *e;
    while ((e = readdir(d))) {
        const char *name = e->d_name;
        if (name[0] < '0' || name[0] > '9') continue;
        char p[128], b[512];
        snprintf(p, sizeof(p), "/proc/%s/comm", name);
        int f = open(p, O_RDONLY);
        char comm[64] = "?";
        if (f >= 0) { int r = read(f, comm, sizeof(comm)-1); if (r > 0) { comm[r] = 0; char *nl = strchr(comm, '\n'); if (nl) *nl = 0; } close(f); }
        snprintf(p, sizeof(p), "/proc/%s/wchan", name);
        f = open(p, O_RDONLY);
        char wchan[128] = "?";
        if (f >= 0) { int r = read(f, wchan, sizeof(wchan)-1); if (r > 0) { wchan[r] = 0; } close(f); }
        snprintf(p, sizeof(p), "/proc/%s/stat", name);
        f = open(p, O_RDONLY);
        char st[1024] = "";
        if (f >= 0) { int r = read(f, st, sizeof(st)-1); if (r > 0) st[r] = 0; close(f);
            // state is after last ')'
            char *rp = strrchr(st, ')');
            if (rp && rp[1] == ' ') { char state = rp[2]; snprintf(b, sizeof(b), "%-6s %-22s state=%c wchan=%s\n", name, comm, state, wchan); }
            else snprintf(b, sizeof(b), "%-6s %-22s wchan=%s\n", name, comm, wchan);
        } else snprintf(b, sizeof(b), "%-6s %-22s wchan=%s\n", name, comm, wchan);
        wstr(b);
    }
    closedir(d);
    wstr("\n");
}

int main(void) {
    mkdir("/metadata/gsi/dsu", 0771);
    out = open("/metadata/gsi/dsu/probe.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) _exit(1);
    wstr("=== DIAG PROBE START ===\n");
    fsync(out);

    for (int i = 0; i < 12; i++) {
        char hdr[128];
        int n = snprintf(hdr, sizeof(hdr), "\n########## ROUND %d ##########\n", i + 1);
        wstr(hdr);
        dump_file("/proc/1/wchan", "init wchan");
        dump_file("/proc/1/stack", "init stack");
        dump_file("/proc/1/status", "init status");
        dump_file("/proc/mounts", "mounts");
        dump_procs();
        fsync(out);
        sleep(3);
    }
    wstr("=== DIAG PROBE END ===\n");
    fsync(out);
    close(out);
    return 0;
}

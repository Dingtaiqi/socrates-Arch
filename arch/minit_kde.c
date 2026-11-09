/*
 * minit_v18.c — 基于 v17，新增：可选 Weston 桌面自动启动 + /dev/uinput 节点
 *
 * v18 改动（相对 v17）：
 *   - 解析 --weston / env START_WESTON=1 / /system/etc/arch/init.args 中的 --weston
 *   - shell（ttyGS0）建立后，若显式请求：mkdir /run/user/0(0700) →
 *     **先起 seatd（/usr/bin/seatd -g root，DRM backend 的 libseat 依赖）** →
 *     chroot(overlay 根 /mnt) → exec weston -B drm --drm-device=card0 --renderer=pixman
 *       --seat=seat0 --idle-time=0 --log=/dev/weston.log
 *   - weston 立即退出时自动换 --drm-device=/dev/dri/card0 重试一次（并写 WESTON-RETRY）
 *   - 背光仅在显式启动 weston 时写 max（OLED 保护：默认不启动、保持黑屏）
 *   - weston 崩溃自动写 WESTON-EXIT 到 /metadata/p0_boot.log，不阻塞 shell
 *   - 启动早期 mknod /dev/uinput (10:223)，供 uinput_input 注入鼠标/键盘
 *
 * 依赖 rootfs：weston、mesa(pixman)、libinput、seatd/logind（或 root 直接启动）
 * 编译：aarch64-linux-gnu-gcc -O2 -static -o minit_v18 minit_v18.c
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/loop.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* 前置声明：mknod_uinput 在 weston 块中先使用后定义（v18.1 patcher 误删定义后合并） */
static void mknod_uinput(void);

static int g_log = -1;
static int g_kmsg = -1;
static int g_selftest = 0;
static const char *g_log_path = "/metadata/p0_boot.log";

/* Test A/D：dwc3 链（按 modules.dep/softdep 顺序；缺文件跳过并记录） */
static const char *g_mods[] = {
    "/vendor/lib/modules/pdr_interface.ko",
    "/vendor/lib/modules/qmi_helpers.ko",
    "/vendor/lib/modules/glink_probe.ko",
    "/vendor/lib/modules/glink_pkt.ko",
    "/vendor/lib/modules/pmic_glink.ko",
    "/vendor/lib/modules/charger-ulog-glink.ko",
    "/vendor/lib/modules/altmode-glink.ko",
    "/vendor/lib/modules/eud.ko",
    "/vendor/lib/modules/usb_bam.ko",
    "/vendor/lib/modules/sps_drv.ko",
    "/vendor/lib/modules/phy-msm-ssusb-qmp.ko",
    "/vendor/lib/modules/phy-msm-snps-eusb2.ko",
    "/vendor/lib/modules/phy-msm-m31-eusb2.ko",
    "/vendor/lib/modules/dwc3-msm.ko",
    "/vendor/lib/modules/ucsi_glink.ko",
    "/vendor/lib/modules/repeater.ko",
    "/vendor/lib/modules/repeater-qti-pmic-eusb2.ko",
    "/vendor/lib/modules/repeater-i2c-eusb2.ko",
    "/vendor/lib/modules/redriver.ko",
    "/vendor/lib/modules/rproc_qcom_common.ko",
    "/vendor/lib/modules/qcom_glink.ko",
    "/vendor/lib/modules/qcom_glink_smem.ko",
    NULL
};

static void mkdir_p(const char *path, mode_t mode) {
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = 0; mkdir(tmp, mode); *p = '/'; }
    }
    mkdir(tmp, mode);
}

static int mknode(const char *path, mode_t mode, unsigned int major, unsigned int minor) {
    if (access(path, F_OK) == 0) return 0;
    return mknod(path, mode, makedev(major, minor));
}

static void flog(const char *fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if (n > (int)sizeof(buf) - 1) n = sizeof(buf) - 1;
    if (g_log >= 0) {
        char line[2100];
        int m = snprintf(line, sizeof(line), "%s\n", buf);
        if (m > 0) { ssize_t ig = write(g_log, line, m); (void)ig; }
    }
    if (g_kmsg >= 0) {
        char line[2100];
        int m = snprintf(line, sizeof(line), "minit: %s\n", buf);
        if (m > 0) { ssize_t ig = write(g_kmsg, line, m); (void)ig; }
    }
    fprintf(stderr, "[minit] %s\n", buf);
}

static void fail_step(const char *step) {
    int e = errno;
    flog("FAIL step=%s errno=%d (%s)", step, e, strerror(e));
    sync();
    if (g_selftest) _exit(2);
    sleep(300);
    reboot(RB_AUTOBOOT);
    _exit(0);
}

static int write_file(const char *path, const char *val) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n = write(fd, val, strlen(val));
    close(fd);
    return n == (ssize_t)strlen(val) ? 0 : -1;
}

static int read_file(const char *path, char *buf, size_t sz) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, sz - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    char *nl = strchr(buf, '\n'); if (nl) *nl = 0;
    return 0;
}


/* dmesg 末尾 n 行（失败现场） */
static void dump_dmesg_tail(int n) {
    char *buf = malloc(1 << 20);
    if (!buf) return;
    long r = syscall(SYS_syslog, 3 /* SYSLOG_ACTION_READ_ALL */, buf, 1 << 20);
    if (r <= 0) { flog("DMESG tail 读取失败 errno=%d", errno); free(buf); return; }
    long end = r;
    int lines = 0;
    for (long i = r - 1; i >= 0 && lines <= n; i--) {
        if (buf[i] == '\n') { lines++; if (lines == n + 1) { end = i; break; } }
    }
    flog("DMESG-TAIL-BEGIN");
    char *p = buf + end;
    while (*p) {
        char *nl = strchr(p, '\n');
        if (nl) *nl = 0;
        if (*p) flog("DMESG %s", p);
        if (!nl) break;
        p = nl + 1;
    }
    flog("DMESG-TAIL-END");
    free(buf);
}

static void dump_mounts(int max) {
    FILE *f = fopen("/proc/mounts", "re");
    if (!f) { flog("WARN /proc/mounts 打不开 errno=%d", errno); return; }
    char line[1024];
    int n = 0;
    while (n < max && fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n'); if (nl) *nl = 0;
        flog("MOUNT %s", line);
        n++;
    }
    fclose(f);
    flog("MOUNTS-DUMPED %d lines", n);
}

static void dump_dir(const char *path, int max) {
    DIR *d = opendir(path);
    if (!d) { flog("WARN opendir %s errno=%d (%s)", path, errno, strerror(errno)); return; }
    struct dirent *de;
    int n = 0;
    while (n < max && (de = readdir(d))) {
        if (de->d_name[0] == '.') continue;
        flog("DIR %s: %s", path, de->d_name);
        n++;
    }
    closedir(d);
    flog("DIR %s dumped %d entries", path, n);
}

static void try_open_log(void) {
    int fd = open(g_log_path, O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
    if (fd >= 0) g_log = fd;
}

static int mount_metadata(void) {
    mkdir_p("/metadata", 0755);
    try_open_log();
    if (g_log >= 0) { flog("METADATA-MOUNTED src=existing"); return 0; }
    const char *cands[] = {"/dev/block/by-name/metadata", "/dev/block/sda17", NULL};
    for (int i = 0; cands[i]; i++) {
        if (access(cands[i], F_OK) != 0) { flog("META-CAND %s not-exist", cands[i]); continue; }
        if (mount(cands[i], "/metadata", "ext4", MS_NOATIME, NULL) == 0 ||
            mount(cands[i], "/metadata", "f2fs", MS_NOATIME, NULL) == 0) {
            try_open_log();
            if (g_log >= 0) { flog("METADATA-MOUNTED src=%s", cands[i]); return 0; }
        }
        flog("META-CAND %s mount-fail errno=%d", cands[i], errno);
    }
    DIR *d = opendir("/sys/class/block");
    if (d) {
        struct dirent *de;
        while ((de = readdir(d))) {
            if (de->d_name[0] == '.') continue;
            char uev[256], line[256];
            snprintf(uev, sizeof(uev), "/sys/class/block/%s/uevent", de->d_name);
            FILE *f = fopen(uev, "re");
            if (!f) continue;
            int is_meta = 0;
            while (fgets(line, sizeof(line), f)) {
                if (strstr(line, "PARTNAME=metadata")) { is_meta = 1; break; }
            }
            fclose(f);
            if (!is_meta) continue;
            char devf[256], buf[64];
            snprintf(devf, sizeof(devf), "/sys/class/block/%s/dev", de->d_name);
            if (read_file(devf, buf, sizeof(buf)) != 0) continue;
            unsigned maj = 0, min = 0;
            if (sscanf(buf, "%u:%u", &maj, &min) != 2) continue;
            char node[128];
            snprintf(node, sizeof(node), "/dev/block/%s", de->d_name);
            mkdir_p("/dev/block", 0755);
            mknode(node, S_IFBLK | 0600, maj, min);
            flog("META-SCAN %s=%u:%u", de->d_name, maj, min);
            if (mount(node, "/metadata", "ext4", MS_NOATIME, NULL) == 0 ||
                mount(node, "/metadata", "f2fs", MS_NOATIME, NULL) == 0) {
                try_open_log();
                if (g_log >= 0) { flog("METADATA-MOUNTED src=%s", node); closedir(d); return 0; }
            }
            flog("META-SCAN mount-fail node=%s errno=%d", node, errno);
        }
        closedir(d);
    }
    flog("WARN metadata 不可写，仅 kmsg");
    return -1;
}


/* v14: 从 /proc/cmdline 提取 "<modname>.*" 参数，作为 finit_module 的 args 传入。
   内核不会把 cmdline 里的模块参数自动应用到后加载模块（实测 msm_drm.dsi_display0 为空），
   必须显式传给 finit_module，否则 msm_drm 选错面板（黑屏）。 */
static int build_mod_args(const char *modname, char *out, size_t sz)
{
    out[0] = 0;
    int fd = open("/proc/cmdline", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    char buf[8192];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = 0;
    char prefix[160];
    snprintf(prefix, sizeof(prefix), "%s.", modname);
    size_t plen = strlen(prefix);
    int cnt = 0;
    for (char *tok = strtok(buf, " \t\n"); tok; tok = strtok(NULL, " \t\n")) {
        if (strncmp(tok, prefix, plen) != 0) continue;
        size_t cur = strlen(out);
        size_t add = strlen(tok + plen);
        if (cur + add + 2 >= sz) break;
        if (cur) { out[cur++] = ' '; out[cur] = 0; }
        strncat(out, tok + plen, sz - strlen(out) - 1);
        cnt++;
    }
    return cnt;
}

static void mod_name_from_path(const char *path, char *name, size_t sz)
{
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    snprintf(name, sz, "%s", base);
    char *dot = strstr(name, ".ko");
    if (dot) *dot = 0;
    for (char *q = name; *q; q++) if (*q == '-') *q = '_';
}

static int module_loaded(const char *path)
{
    /* 检查 /sys/module/<name> 是否存在（name=去掉目录与 .ko，- 变 _） */
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    char name[128];
    snprintf(name, sizeof(name), "%s", base);
    char *dot = strstr(name, ".ko");
    if (dot) *dot = 0;
    for (char *q = name; *q; q++) if (*q == '-') *q = '_';
    char sp[192];
    snprintf(sp, sizeof(sp), "/sys/module/%s", name);
    return access(sp, F_OK) == 0;
}

static void load_modules_from_list(void)
{
    const char *list = "/vendor/lib/modules/modules.load";
    FILE *f = fopen(list, "re");
    if (!f) {
        flog("MODLIST open-fail %s errno=%d (%s)", list, errno, strerror(errno));
        return;
    }
    static char lines[520][160];
    int n = 0;
    char buf[256];
    while (fgets(buf, sizeof(buf), f) && n < 520) {
        char *p = buf;
        while (*p == ' ' || *p == '\t') p++;
        char *e = p + strlen(p);
        while (e > p && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ')) *--e = 0;
        if (!*p || *p == '#') continue;
        snprintf(lines[n], sizeof(lines[n]), "%s", p);
        n++;
    }
    fclose(f);
    flog("MODLIST %s lines=%d", list, n);

    /* v13: 多变轮把除 msm_drm 外全部加载完（直到一轮无新增），再单独加载 msm_drm 并重试，
       保证内核 cmdline 的 msm_drm.dsi_display0=... 参数第一次成功加载时才被消费（选对面板）。 */
    int total_added = 0;
    for (int round = 0; round < 12; round++) {
        int ok = 0, fail = 0, already = 0, added = 0;
        for (int i = 0; i < n; i++) {
            if (strstr(lines[i], "msm_drm.ko")) continue;
            char path[256];
            snprintf(path, sizeof(path), "/vendor/lib/modules/%s", lines[i]);
            if (module_loaded(path)) { already++; continue; }
            int fd = open(path, O_RDONLY | O_CLOEXEC);
            if (fd < 0) { fail++; continue; }
            char mname[128], margs[1024];
            mod_name_from_path(path, mname, sizeof(mname));
            build_mod_args(mname, margs, sizeof(margs));
            long rc = syscall(SYS_finit_module, fd, margs, 0);
            int er = errno;
            close(fd);
            if (rc == 0 || er == EEXIST) {
                if (strncmp(mname, "msm_drm", 7) == 0)
                    flog("MODARGS %s = [%s]", mname, margs);
            }
            if (rc == 0) { ok++; added++; }
            else if (er == EEXIST) { already++; }
            else { fail++; if (round == 0) flog("MOD r0 fail %s errno=%d", lines[i], er); }
        }
        total_added += added;
        flog("MODROUND %d ok=%d added=%d already=%d fail=%d total=%d", round, ok, added, already, fail, n);
        if (added == 0) break;
    }
    flog("MODROUND-DONE total_added=%d", total_added);

    /* 现在所有依赖都加载了，反复尝试 msm_drm（每次失败后再扫一轮补漏） */
    const char *dm = "/vendor/lib/modules/msm_drm.ko";
    for (int k = 0; k < 6 && !module_loaded(dm); k++) {
        int fd = open(dm, O_RDONLY | O_CLOEXEC);
        if (fd < 0) { flog("MOD msm_drm open-fail errno=%d (%s)", errno, strerror(errno)); break; }
        char dmargs[1024];
        int nargs = build_mod_args("msm_drm", dmargs, sizeof(dmargs));
        flog("MOD msm_drm args=%d [%s]", nargs, dmargs);
        long rc = syscall(SYS_finit_module, fd, dmargs, 0);
        int er = errno;
        close(fd);
        flog("MOD msm_drm attempt=%d rc=%ld errno=%d (%s)", k + 1, rc, er, strerror(er));
        if (rc == 0 || er == EEXIST) break;
        /* 失败：再补一轮其它模块，然后重试 */
        int added = 0;
        for (int i = 0; i < n; i++) {
            if (strstr(lines[i], "msm_drm.ko")) continue;
            char path[256];
            snprintf(path, sizeof(path), "/vendor/lib/modules/%s", lines[i]);
            if (module_loaded(path)) continue;
            int f2 = open(path, O_RDONLY | O_CLOEXEC);
            if (f2 < 0) continue;
            char mn2[128], ma2[1024];
            mod_name_from_path(path, mn2, sizeof(mn2));
            build_mod_args(mn2, ma2, sizeof(ma2));
            long r2 = syscall(SYS_finit_module, f2, ma2, 0);
            int e2 = errno;
            close(f2);
            if (r2 == 0) { added++; continue; }
            if (e2 != EEXIST) { /* 记录前 3 个失败名 */ }
        }
        flog("MOD msm_drm retry-supplement added=%d", added);
        usleep(300 * 1000);
    }
    flog("MOD msm_drm loaded=%d", module_loaded(dm));
    {
        char pv[128] = {0};
        if (read_file("/sys/module/msm_drm/parameters/dsi_display0", pv, sizeof(pv)) == 0)
            flog("PARAM dsi_display0='%s'", pv);
        else
            flog("PARAM dsi_display0 read-fail errno=%d (%s)", errno, strerror(errno));
    }

    dump_dir("/sys/class/udc", 10);
    dump_dir("/sys/class/usb_role", 10);
}

static void load_dwc3_chain(void) {
    flog("STEP insmod-dwc3-chain");
    for (int i = 0; g_mods[i]; i++) {
        int fd = open(g_mods[i], O_RDONLY | O_CLOEXEC);
        if (fd < 0) { flog("MOD %s open-fail errno=%d (%s)", g_mods[i], errno, strerror(errno)); continue; }
        long rc = syscall(SYS_finit_module, fd, "", 0);
        int e = errno;
        close(fd);
        if (rc == 0) flog("MOD ok %s", g_mods[i]);
        else if (e == EEXIST) flog("MOD already %s", g_mods[i]);
        else flog("MOD fail %s errno=%d (%s)", g_mods[i], e, strerror(e));
    }
    /* 加载后再看一眼 */
    dump_dir("/sys/class/udc", 10);
}

static void unbind_all_gadgets(void) {
    DIR *d = opendir("/sys/kernel/config/usb_gadget");
    if (!d) { flog("WARN opendir usb_gadget errno=%d (%s)", errno, strerror(errno)); return; }
    struct dirent *de;
    while ((de = readdir(d))) {
        if (de->d_name[0] == '.') continue;
        char udc[256], buf[128] = {0};
        snprintf(udc, sizeof(udc), "/sys/kernel/config/usb_gadget/%s/UDC", de->d_name);
        read_file(udc, buf, sizeof(buf));
        flog("GADGET-EXISTING %s UDC='%s'", de->d_name, buf);
        int rc = write_file(udc, "");
        flog("GADGET-UNBIND %s rc=%d errno=%d", de->d_name, rc, errno);
        usleep(100 * 1000);
    }
    closedir(d);
}

/* chroot 到 /system/arch 跑探针：子进程输出经 pipe 回父进程，父进程写入 /metadata/arch_probe.log（fd 跨 chroot 有效） */
static void probe_chroot_userspace(void) {
    flog("STEP chroot begin root=/system/arch");
    int afd = open("/metadata/arch_probe.log", O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
    if (afd < 0) flog("CHROOT-ERR open /metadata/arch_probe.log errno=%d (%s)", errno, strerror(errno));
    if (access("/system/arch/bin/bash", X_OK) != 0)
        flog("CHROOT-ERR /system/arch/bin/bash 不可执行 errno=%d (%s)", errno, strerror(errno));

    int pfd[2];
    if (pipe(pfd) != 0) { flog("CHROOT-ERR pipe errno=%d", errno); if (afd >= 0) close(afd); return; }
    pid_t pid = fork();
    if (pid == 0) {
        close(pfd[0]);
        if (chroot("/system/arch") != 0) {
            dprintf(2, "CHROOT-FAIL chroot errno=%d\n", errno);
            _exit(127);
        }
        if (chdir("/") != 0) { dprintf(2, "CHROOT-FAIL chdir errno=%d\n", errno); _exit(127); }
        /* 新 root 内挂 pseudo fs（失败也继续） */
        mount("proc", "/proc", "proc", 0, NULL);
        mount("sysfs", "/sys", "sysfs", 0, NULL);
        mount("tmpfs", "/dev", "tmpfs", MS_NOSUID, "mode=755");
        dup2(pfd[1], 1);
        dup2(pfd[1], 2);
        if (pfd[1] > 2) close(pfd[1]);
        char *argv[] = {"/bin/bash", "-c",
                        "echo PROBE-BEGIN; uname -a; echo ---; cat /etc/os-release 2>&1; echo ---; ls /; "
                        "echo ---; mount; echo ---; id; echo PROBE-END",
                        NULL};
        char *env[] = {"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/root", NULL};
        execve("/bin/bash", argv, env);
        dprintf(2, "CHROOT-FAIL exec bash errno=%d\n", errno);
        _exit(127);
    }
    close(pfd[1]);
    char buf[4096];
    ssize_t n;
    int total = 0;
    while ((n = read(pfd[0], buf, sizeof(buf))) > 0) {
        if (afd >= 0) { ssize_t ig = write(afd, buf, n); (void)ig; }
        total += (int)n;
    }
    close(pfd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    int rc = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    if (afd >= 0) close(afd);
    flog("PROBE-DONE rc=%d bytes=%d log=/metadata/arch_probe.log", rc, total);
}

static int setup_gadget(void) {
    mkdir_p("/sys", 0555);
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0 && errno != EBUSY)
        flog("warn mount sys errno=%d", errno);
    mkdir_p("/sys/kernel/config", 0755);
    if (mount("configfs", "/sys/kernel/config", "configfs", 0, NULL) != 0 && errno != EBUSY)
        flog("gadget: mount configfs fail errno=%d (%s)", errno, strerror(errno));
    else
        flog("gadget: configfs mounted");

    unbind_all_gadgets();
    dump_dir("/sys/class/udc", 10);

    const char *gd = "/sys/kernel/config/usb_gadget/arch";
    int rc = mkdir(gd, 0755);
    flog("gadget: mkdir %s rc=%d errno=%d", gd, rc, errno);
    char p[512];
#define W(attr, val) do { snprintf(p, sizeof(p), "%s/%s", gd, attr); \
    rc = write_file(p, val); flog("gadget: write %s='%s' rc=%d errno=%d", attr, val, rc, errno); } while (0)
    W("idVendor", "0x1d6b");
    W("idProduct", "0x0104");
    W("bcdUSB", "0x0200");
    W("bcdDevice", "0x0100");
    mkdir_p("/sys/kernel/config/usb_gadget/arch/strings/0x409", 0755);
    W("strings/0x409/serialnumber", "ARCHP0T1");
    W("strings/0x409/manufacturer", "ArchLinux");
    W("strings/0x409/product", "Arch P0 Serial");
    mkdir_p("/sys/kernel/config/usb_gadget/arch/configs/c.1", 0755);
    mkdir_p("/sys/kernel/config/usb_gadget/arch/configs/c.1/strings/0x409", 0755);
    W("configs/c.1/strings/0x409/configuration", "acm");
    W("configs/c.1/MaxPower", "500");
    rc = mkdir("/sys/kernel/config/usb_gadget/arch/functions/acm.gs0", 0755);
    flog("gadget: mkdir functions/acm.gs0 rc=%d errno=%d", rc, errno);
    snprintf(p, sizeof(p), "%s/configs/c.1/acm.gs0", gd);
    rc = symlink("/sys/kernel/config/usb_gadget/arch/functions/acm.gs0", p);
    flog("gadget: symlink acm.gs0 rc=%d errno=%d", rc, errno);

    /* v19: USB NCM 网络功能（与 acm 同 config，开机即可用） */
    snprintf(p, sizeof(p), "%s/functions/ncm.0", gd);
    rc = mkdir(p, 0755);
    flog("gadget: mkdir functions/ncm.0 rc=%d errno=%d", rc, errno);
    snprintf(p, sizeof(p), "%s/functions/ncm.0/dev_addr", gd);
    rc = write_file(p, "02:11:22:33:44:55");
    flog("gadget: write ncm dev_addr rc=%d errno=%d", rc, errno);
    snprintf(p, sizeof(p), "%s/configs/c.1/ncm.0", gd);
    rc = symlink("/sys/kernel/config/usb_gadget/arch/functions/ncm.0", p);
    flog("gadget: symlink ncm.0 rc=%d errno=%d", rc, errno);

    char udc[128] = {0};
    DIR *d = opendir("/sys/class/udc");
    if (d) {
        struct dirent *de;
        while ((de = readdir(d))) {
            if (de->d_name[0] == '.') continue;
            snprintf(udc, sizeof(udc), "%s", de->d_name);
            break;
        }
        closedir(d);
    }
    if (!udc[0]) { flog("gadget: NO-UDC（dwc3 未加载或 UDC 未注册）"); return -1; }
    flog("gadget: use UDC=%s", udc);
    snprintf(p, sizeof(p), "%s/UDC", gd);
    write_file(p, "");
    usleep(200 * 1000);
    for (int i = 0; i < 3; i++) {
        rc = write_file(p, udc);
        flog("gadget: bind UDC attempt=%d rc=%d errno=%d", i + 1, rc, errno);
        if (rc == 0) {
            char buf[64] = {0};
            if (read_file("/sys/class/tty/ttyGS0/dev", buf, sizeof(buf)) == 0)
                flog("GADGET-OK UDC=%s ttyGS0_dev=%s", udc, buf);
            else
                flog("GADGET-OK UDC=%s ttyGS0_dev=(not-yet) errno=%d", udc, errno);
            return 0;
        }
        write_file(p, "");
        usleep(300 * 1000);
    }
    return -1;
}


/* ===== minit v4: USB role 强制 + ttyGS0 Arch shell ===== */
static int write_role_all(void)
{
    /* 扫描 /sys/class/usb_role/*：把每个 role 写成 device（不同机型名字不同） */
    int wrote = 0;
    DIR *d = opendir("/sys/class/usb_role");
    if (!d) {
        flog("USB-ROLE: opendir /sys/class/usb_role fail errno=%d (%s)", errno, strerror(errno));
    } else {
        struct dirent *de;
        while ((de = readdir(d))) {
            if (de->d_name[0] == '.') continue;
            char rp[512], rb[64] = {0};
            snprintf(rp, sizeof(rp), "/sys/class/usb_role/%s/role", de->d_name);
            int rc = write_file(rp, "device");
            read_file(rp, rb, sizeof(rb));
            flog("USB-ROLE %s <- device rc=%d errno=%d readback='%s'", rp, rc, errno, rb);
            wrote++;
        }
        closedir(d);
    }
    /* 扫描 /sys/devices/platform/soc 下 ssusb 设备的 mode 节点 */
    DIR *p = opendir("/sys/devices/platform/soc");
    if (p) {
        struct dirent *de;
        while ((de = readdir(p))) {
            if (de->d_name[0] == '.') continue;
            if (!strstr(de->d_name, "ssusb") && !strstr(de->d_name, "dwc3")) continue;
            char mp[512];
            snprintf(mp, sizeof(mp), "/sys/devices/platform/soc/%s/mode", de->d_name);
            int rc = write_file(mp, "peripheral");
            flog("USB-MODE %s <- peripheral rc=%d errno=%d", mp, rc, errno);
            wrote++;
        }
        closedir(p);
    }
    return wrote > 0 ? 0 : -1;
}

static int force_usb_role(void)
{
    int rc = write_role_all();
    flog("USB-ROLE write_all rc=%d", rc);
    return rc;
}

static int udc_present(void)
{
    DIR *d = opendir("/sys/class/udc");
    if (!d) return 0;
    int found = 0;
    struct dirent *de;
    while ((de = readdir(d))) {
        if (de->d_name[0] == '.') continue;
        flog("UDC-POLL found %s", de->d_name);
        found = 1;
        break;
    }
    closedir(d);
    return found;
}

static int wait_udc(int tries)
{
    for (int i = 0; i < tries; i++) {
        if (udc_present()) { flog("UDC-POLL ok attempt=%d", i + 1); return 0; }
        if (i > 0 && (i % 4) == 0) {
            flog("UDC-POLL 重新写 usb role/mode（attempt=%d）", i + 1);
            force_usb_role();
        }
        usleep(500 * 1000);
    }
    flog("UDC-POLL none after %d tries（%dms）", tries, tries * 500);
    dump_dmesg_tail(5);
    return -1;
}

/* Only mount a deliberately provisioned DSU data filesystem. Never format
 * devices here, and never infer that an unknown/empty device is disposable. */
static int mount_persistent_data(void)
{
    char expected[80], path[256], name[80], dev[80];
    if (read_file("/system/etc/arch/persist.uuid", expected, sizeof(expected)) != 0)
        return -1;
    expected[strcspn(expected, "\r\n")] = 0;
    if (strlen(expected) != 36) return -1;
    DIR *dir = opendir("/sys/class/block");
    if (!dir) return -1;
    int result = -1;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (strncmp(entry->d_name, "dm-", 3)) continue;
        snprintf(path, sizeof(path), "/sys/class/block/%s/dm/name", entry->d_name);
        if (read_file(path, name, sizeof(name)) != 0) continue;
        name[strcspn(name, "\r\n")] = 0;
        if (strcmp(name, "userdata_gsi")) continue;
        snprintf(path, sizeof(path), "/sys/class/block/%s/dev", entry->d_name);
        unsigned major, minor;
        if (read_file(path, dev, sizeof(dev)) != 0 || sscanf(dev, "%u:%u", &major, &minor) != 2) break;
        const char *node = "/dev/kde-dsu-data";
        if (mknode(node, S_IFBLK | 0600, major, minor) != 0) break;
        struct stat st;
        if (stat(node, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != makedev(major, minor)) break;
        int fd = open(node, O_RDONLY | O_CLOEXEC);
        if (fd < 0) break;
        unsigned char sb[128];
        ssize_t bytes = pread(fd, sb, sizeof(sb), 1024);
        close(fd);
        if (bytes != sizeof(sb) || sb[56] != 0x53 || sb[57] != 0xef) break;
        char uuid[37];
        snprintf(uuid, sizeof(uuid),
                 "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                 sb[104], sb[105], sb[106], sb[107], sb[108], sb[109], sb[110], sb[111],
                 sb[112], sb[113], sb[114], sb[115], sb[116], sb[117], sb[118], sb[119]);
        if (strcmp(expected, uuid)) { flog("PERSIST: userdata UUID differs; leaving it untouched"); break; }
        mkdir_p("/dev/kde-persist", 0700);
        if (mount(node, "/dev/kde-persist", "ext4", MS_NOATIME, NULL) != 0) break;
        char marker[80];
        if (read_file("/dev/kde-persist/.kde-dsu-volume", marker, sizeof(marker)) != 0 ||
            strncmp(marker, expected, 36)) {
            umount("/dev/kde-persist");
            break;
        }
        result = 0;
        flog("PERSIST: verified DSU userdata uuid=%s", uuid);
        break;
    }
    closedir(dir);
    return result;
}

/* A verified DSU data filesystem supplies persistent upper/work. A RAM
 * fallback retains the serial recovery shell before initial provisioning. */
static int try_overlay_root(char *newroot, size_t sz)
{
    int persistent = mount_persistent_data() == 0;
    const char *upper = persistent ? "/dev/kde-persist/upper" : "/dev/arch_upper";
    const char *work = persistent ? "/dev/kde-persist/work" : "/dev/arch_work";
    mkdir_p(upper, 0755);
    mkdir_p(work, 0755);
    mkdir_p("/mnt", 0755);
    char opt[512];
    snprintf(opt, sizeof(opt), "lowerdir=/system/arch,upperdir=%s,workdir=%s", upper, work);
    int rc = mount("overlay", "/mnt", "overlay", 0, opt);
    flog("OVERLAY mount rc=%d errno=%d (%s)", rc, errno, strerror(errno));
    if (rc != 0) return -1;
    /* 把 /dev /proc /sys 绑进去 */
    mkdir_p("/mnt/dev", 0755); mkdir_p("/mnt/proc", 0555); mkdir_p("/mnt/sys", 0555);
    int r1 = mount("/dev", "/mnt/dev", NULL, MS_BIND | MS_REC, NULL);
    int r2 = mount("/proc", "/mnt/proc", NULL, MS_BIND | MS_REC, NULL);
    int r3 = mount("/sys", "/mnt/sys", NULL, MS_BIND | MS_REC, NULL);
    flog("OVERLAY bind dev=%d proc=%d sys=%d errno=%d", r1, r2, r3, errno);
    if (r1 != 0 || r2 != 0 || r3 != 0) return -1;
    int ready = open("/dev/kde-overlay-ready", O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
    if (ready < 0) return -1;
    close(ready);
    snprintf(newroot, sz, "%s", "/mnt");
    flog("OVERLAY-OK root=/mnt (rw, persistent=%d)", persistent);
    return 0;
}

static int shell_on_ttygs(void)
{
    char buf[64] = {0};
    /* v6: ACM 绑定后 ttyGS0/dev 可能晚几十~几百 ms 出现，poll 3s */
    int got = -1;
    for (int i = 0; i < 15; i++) {
        if (read_file("/sys/class/tty/ttyGS0/dev", buf, sizeof(buf)) == 0) { got = 0; break; }
        if (i == 0) flog("SHELL: ttyGS0/dev 未就绪，poll… errno=%d", errno);
        usleep(200 * 1000);
    }
    if (got != 0) {
        flog("SHELL: no ttyGS0/dev after 3s errno=%d", errno);
        dump_dmesg_tail(5);
        return -1;
    }
    flog("SHELL: ttyGS0/dev ready '%s'", buf);
    unsigned maj = 0, min = 0;
    if (sscanf(buf, "%u:%u", &maj, &min) != 2) {
        flog("SHELL: bad ttyGS0 dev '%s'", buf);
        return -1;
    }
    mknode("/dev/ttyGS0", S_IFCHR | 0600, maj, min);
    int fd = open("/dev/ttyGS0", O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        flog("SHELL: open ttyGS0 fail errno=%d (%s)", errno, strerror(errno));
        return -1;
    }
    int fd_flags = fcntl(fd, F_GETFL);
    if (fd_flags >= 0) fcntl(fd, F_SETFL, fd_flags & ~O_NONBLOCK);
    flog("SHELL-ATTACH ttyGS0 fd=%d dev=%s", fd, buf);
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        ioctl(fd, TIOCSCTTY, 0);
        dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
        if (fd > 2) close(fd);
        char nroot[64] = {0};
        if (try_overlay_root(nroot, sizeof(nroot)) != 0) {
            snprintf(nroot, sizeof(nroot), "%s", "/system/arch");
            mkdir_p("/system/arch/dev", 0755);
            mkdir_p("/system/arch/proc", 0555);
            mkdir_p("/system/arch/sys", 0555);
            mount("/dev", "/system/arch/dev", NULL, MS_BIND | MS_REC, NULL);
            mount("/proc", "/system/arch/proc", NULL, MS_BIND | MS_REC, NULL);
            mount("/sys", "/system/arch/sys", NULL, MS_BIND | MS_REC, NULL);
            flog("SHELL: fallback chroot root=/system/arch (ro)");
        }
        if (chroot(nroot) != 0)
            flog("SHELL: chroot fail errno=%d", errno);
        chdir("/");
        setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
        setenv("HOME", "/root", 1);
        setenv("TERM", "dumb", 1);
        execl("/bin/bash", "bash", "-i", (char *)NULL);
        execl("/bin/sh", "sh", "-i", (char *)NULL);
        _exit(127);
    }
    flog("SHELL-STARTED pid=%d", (int)pid);
    return 0;
}


/* ===== minit v10: P1 点屏（mknod /dev/dri/card0 -> chroot -> drm_demo -> /metadata/p1_display.log） ===== */
static void write_max_backlight(void)
{
    DIR *d = opendir("/sys/class/backlight");
    if (!d) { flog("P1: no /sys/class/backlight errno=%d", errno); return; }
    struct dirent *de;
    while ((de = readdir(d))) {
        if (de->d_name[0] == '.') continue;
        char mb[256], br[256], buf[32] = {0};
        snprintf(mb, sizeof(mb), "/sys/class/backlight/%s/max_brightness", de->d_name);
        snprintf(br, sizeof(br), "/sys/class/backlight/%s/brightness", de->d_name);
        if (read_file(mb, buf, sizeof(buf)) == 0) {
            char *e = buf; while (*e == ' ' || *e == '\n' || *e == '\t') e++;
            int rc = write_file(br, e);
            flog("P1: backlight %s max='%s' write rc=%d errno=%d", de->d_name, e, rc, errno);
        }
    }
    closedir(d);
}

static int mknod_drm_card(void)
{
    char buf[64] = {0};
    if (read_file("/sys/class/drm/card0/dev", buf, sizeof(buf)) != 0) {
        flog("P1: no /sys/class/drm/card0/dev errno=%d (%s)", errno, strerror(errno));
        return -1;
    }
    unsigned maj = 0, min = 0;
    if (sscanf(buf, "%u:%u", &maj, &min) != 2) { flog("P1: bad card0 dev '%s'", buf); return -1; }
    mkdir_p("/dev/dri", 0755);
    mknode("/dev/dri/card0", S_IFCHR | 0666, maj, min);
    flog("P1: mknod /dev/dri/card0 %s ok", buf);
    mkdir_p("/system/arch/dev", 0755);
    int rc = mount("/dev", "/system/arch/dev", NULL, MS_BIND | MS_REC, NULL);
    flog("P1: bind /dev -> rootfs/dev rc=%d errno=%d", rc, errno);
    return 0;
}

/* v15: 从 sysfs 为 /sys/class/input/event* 建 /dev/input/eventX 节点（触摸/按键） */
static void mknod_input_devices(void)
{
    mkdir_p("/dev/input", 0755);
    DIR *d = opendir("/sys/class/input");
    if (!d) { flog("INPUT: no /sys/class/input errno=%d", errno); return; }
    struct dirent *de;
    int made = 0;
    while ((de = readdir(d))) {
        if (strncmp(de->d_name, "event", 5) != 0) continue;
        char dp[320], np[128], buf[32] = {0};
        snprintf(dp, sizeof(dp), "/sys/class/input/%s/dev", de->d_name);
        if (read_file(dp, buf, sizeof(buf)) != 0) continue;
        unsigned maj = 0, min = 0;
        if (sscanf(buf, "%u:%u", &maj, &min) != 2) continue;
        snprintf(np, sizeof(np), "/dev/input/%s", de->d_name);
        if (mknode(np, S_IFCHR | 0660, maj, min) == 0) made++;
    }
    closedir(d);
    flog("INPUT: mknod /dev/input nodes made=%d", made);
}

static void run_display_demo(void)
{
    mknod_input_devices();
    write_max_backlight();
    if (mknod_drm_card() != 0) {
        flog("P1: skip demo (no card0)");
        return;
    }
    if (access("/system/arch/usr/local/bin/drm_demo", X_OK) != 0) {
        flog("P1: demo binary missing errno=%d", errno);
        return;
    }
    int afd = open("/dev/p1_display.log", O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
    if (afd < 0) flog("P1: open p1_display.log errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) {
        if (afd >= 0) { dup2(afd, 1); dup2(afd, 2); }
        chroot("/system/arch");
        chdir("/");
        execl("/usr/local/bin/drm_demo", "drm_demo", "--card", "/dev/dri/card0",
              "--pattern", "bars", "--hold", "3600", (char *)NULL);
        if (afd >= 0) { const char *e = "EXEC-FAIL drm_demo\n"; int w = write(2, e, strlen(e)); (void)w; }
        _exit(127);
    }
    flog("P1: demo started pid=%d log=/metadata/p1_display.log", (int)pid);
}


/* ===== minit v18: 可选 Weston 桌面（软件渲染 pixman；默认不启动，OLED 保护） ===== */
static pid_t g_weston_pid = -1;
static pid_t g_seatd_pid = -1;
static int g_weston_variant = 0;   /* 0: --drm-device=card0  1: --drm-device=/dev/dri/card0 */
static int g_weston_retried = 0;

/* 启动 seatd（DRM backend 依赖 libseat；无 systemd/logind 必须先起 seatd） */
static pid_t start_seatd(void)
{
    if (access("/mnt/usr/bin/seatd", X_OK) != 0) {
        flog("SEATD: /usr/bin/seatd 不存在（可试 root 直启 weston）errno=%d", errno);
        return -1;
    }
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (chroot("/mnt") != 0) _exit(127);
        chdir("/");
        setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
        mkdir_p("/run", 0755);
        int lf = open("/dev/seatd.log", O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (lf >= 0) { dup2(lf, 1); dup2(lf, 2); if (lf > 2) close(lf); }
        execl("/usr/bin/seatd", "seatd", "-g", "root", (char *)NULL);
        _exit(127);
    }
    flog("SEATD-STARTED pid=%d log=/dev/seatd.log", (int)pid);
    for (int i = 0; i < 30; i++) {
        if (access("/mnt/run/seatd.sock", F_OK) == 0) {
            flog("SEATD-SOCKET ready attempt=%d", i + 1);
            return pid;
        }
        usleep(100 * 1000);
    }
    flog("SEATD: socket 3s 未就绪（继续启动 weston，若报 seat 错误看 /dev/seatd.log）");
    return pid;
}

static void launch_weston(int variant)
{
    g_weston_variant = variant;
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (chroot("/mnt") != 0) { dprintf(2, "WESTON chroot fail errno=%d\n", errno); _exit(127); }
        chdir("/");
        setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
        setenv("HOME", "/root", 1);
        setenv("TERM", "linux", 1);
        setenv("XDG_RUNTIME_DIR", "/run/user/0", 1);
        setenv("XDG_SEAT", "seat0", 1);
        setenv("XDG_SESSION_TYPE", "wayland", 1);
        setenv("WESTON_LIBINPUT_DEVICE", "", 1);
        setenv("LIBSEAT_BACKEND", "seatd", 1);
        setenv("SEATD_SOCK", "/run/seatd.sock", 1);
        int lf = open("/dev/weston.log", O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (lf >= 0) { dup2(lf, 1); dup2(lf, 2); if (lf > 2) close(lf); }
        if (variant == 0)
            execl("/usr/bin/weston", "weston",
                  "-B", "drm", "--drm-device=card0", "--renderer=pixman",
                  "--seat=seat0", "--idle-time=0", "--log=/dev/weston.log", (char *)NULL);
        else
            execl("/usr/bin/weston", "weston",
                  "-B", "drm", "--drm-device=/dev/dri/card0", "--renderer=pixman",
                  "--seat=seat0", "--idle-time=0", "--log=/dev/weston.log", (char *)NULL);
        dprintf(2, "WESTON exec fail errno=%d\n", errno);
        _exit(127);
    }
    g_weston_pid = pid;
    flog("WESTON-STARTED pid=%d variant=%d log=/dev/weston.log", (int)pid, variant);
}

static void start_weston_desktop(void)
{
    const char *root = "/mnt";   /* shell_on_ttygs 里的 overlay 根（共享 mount ns） */
    flog("WESTON: begin root=%s", root);
    if (access("/mnt/usr/bin/weston", X_OK) != 0) {
        flog("WESTON: /usr/bin/weston 不存在或不可执行（overlay 未挂？errno=%d %s）", errno, strerror(errno));
        return;
    }
    mknod_uinput();
    mknod_input_devices();
    if (mknod_drm_card() != 0) {
        flog("WESTON: 无 /dev/dri/card0，放弃启动");
        return;
    }
    /* 显式 opt-in 才写背光 max（默认黑屏 = OLED 保护） */
    write_max_backlight();
    flog("WESTON: backlight=MAX（显式启动；OLED 有烧屏风险，测试完尽快关闭）");
    /* 运行目录：overlay root 内 /run/user/0 (0700) */
    mkdir_p("/mnt/run", 0755);
    mkdir_p("/mnt/run/user", 0755);
    mkdir_p("/mnt/run/user/0", 0700);
    chmod("/mnt/run/user/0", 0700);
    /* v18.1: 先起 seatd（libseat 需要），再起 weston */
    g_seatd_pid = start_seatd();
    launch_weston(0);
}

static void monitor_weston(void)
{
    if (g_weston_pid <= 0) return;
    int st = 0;
    pid_t r = waitpid(g_weston_pid, &st, WNOHANG);
    if (r == g_weston_pid) {
        int code = WIFEXITED(st) ? WEXITSTATUS(st) : -1;
        flog("WESTON-EXIT status=%d variant=%d (log /dev/weston.log)", code, g_weston_variant);
        g_weston_pid = -1;
        if (!g_weston_retried) {
            g_weston_retried = 1;
            flog("WESTON-RETRY 换 --drm-device 路径重试一次");
            usleep(500 * 1000);
            launch_weston(1);
        }
    }
}


/* ===== 从原始 v18 合并回来的 helper（arch patcher 误删） ===== */

static int init_args_wants_weston(void)
{
    FILE *f = fopen("/system/etc/arch/init.args", "re");
    if (!f) return 0;
    char line[512];
    int want = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "--weston") || strstr(line, "START_WESTON")) { want = 1; break; }
    }
    fclose(f);
    if (want) flog("WESTON: init.args 请求启动");
    return want;
}


static void mknod_uinput(void)
{
    mkdir_p("/dev", 0755);
    if (mknode("/dev/uinput", S_IFCHR | 0660, 10, 223) == 0)
        flog("UINPUT: /dev/uinput 10:223 ready");
    else
        flog("UINPUT: mknod /dev/uinput fail errno=%d (%s)", errno, strerror(errno));
}


/* Optional compressed Arch lower layer; legacy images keep their existing root. */
static int mount_arch_erofs(const char *image, const char *target)
{
    if (access(image, R_OK) != 0) return 0;
    char buf[64], path[128], sysdev[128];
    unsigned major, minor;
    if (read_file("/sys/class/misc/loop-control/dev", buf, sizeof(buf)) != 0 ||
        sscanf(buf, "%u:%u", &major, &minor) != 2) return -1;
    if (mknode("/dev/loop-control", S_IFCHR | 0600, major, minor) != 0) return -1;
    int control = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
    if (control < 0) return -1;
    int index = ioctl(control, LOOP_CTL_GET_FREE);
    close(control);
    if (index < 0) return -1;
    snprintf(sysdev, sizeof(sysdev), "/sys/class/block/loop%d/dev", index);
    if (read_file(sysdev, buf, sizeof(buf)) != 0 ||
        sscanf(buf, "%u:%u", &major, &minor) != 2) return -1;
    snprintf(path, sizeof(path), "/dev/loop%d", index);
    if (mknode(path, S_IFBLK | 0600, major, minor) != 0) return -1;
    int backing = open(image, O_RDONLY | O_CLOEXEC);
    int loop = open(path, O_RDWR | O_CLOEXEC);
    if (backing < 0 || loop < 0) {
        if (backing >= 0) close(backing);
        if (loop >= 0) close(loop);
        return -1;
    }
    int rc = ioctl(loop, LOOP_SET_FD, backing);
    close(backing);
    if (rc == 0) {
        struct loop_info64 info = {0};
        info.lo_flags = LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR;
        snprintf((char *)info.lo_file_name, sizeof(info.lo_file_name), "%s", image);
        rc = ioctl(loop, LOOP_SET_STATUS64, &info);
        if (rc == 0) rc = mount(path, target, "erofs", MS_RDONLY, NULL);
        if (rc != 0) ioctl(loop, LOOP_CLR_FD, 0);
    }
    close(loop);
    flog("EROFS-LOWER mount rc=%d image=%s", rc, image);
    return rc;
}

static int init_args_wants_kde(void)
{
    FILE *f = fopen("/system/etc/arch/init.args", "re");
    if (!f) return 0;
    char line[512];
    int want = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "--kde")) { want = 1; break; }
    }
    fclose(f);
    return want;
}

static void start_kde_desktop(void)
{
    /* The serial-shell child mounts /mnt in our shared mount namespace. */
    int ready = 0;
    for (int i = 0; i < 60; ++i) {
        if (access("/dev/kde-overlay-ready", F_OK) == 0 &&
            access("/mnt/usr/bin/kwin_wayland", X_OK) == 0) { ready = 1; break; }
        usleep(100000);
    }
    if (!ready) { flog("KDE: overlay root not ready; keeping serial console"); return; }
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        int in = open("/dev/null", O_RDONLY);
        int out = open("/dev/kde-startup.log", O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (in < 0 || out < 0) _exit(125);
        dup2(in, 0); dup2(out, 1); dup2(out, 2);
        if (in > 2) close(in);
        if (out > 2) close(out);
        if (chroot("/mnt") != 0 || chdir("/") != 0) _exit(126);
        setenv("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1);
        setenv("HOME", "/root", 1);
        execl("/bin/sh", "sh", "/proc/1/root/system/etc/arch/kde-start.sh", (char *)NULL);
        _exit(127);
    }
    flog("KDE-STARTED pid=%d log=/dev/kde-startup.log", (int)pid);
}

int main(int argc, char **argv) {
    int weston_want = 0;
    int kde_want = init_args_wants_kde();
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--selftest")) g_selftest = 1;
        else if (!strcmp(argv[i], "--log") && i + 1 < argc) g_log_path = argv[++i];
        else if (!strcmp(argv[i], "--weston")) weston_want = 1;
        else if (!strcmp(argv[i], "--kde")) kde_want = 1;
    }
    if (g_selftest) g_log_path = "/tmp/minit_meta.log";
    if (getenv("START_WESTON") && !strcmp(getenv("START_WESTON"), "1")) {
        weston_want = 1;
        fprintf(stderr, "[minit] START_WESTON=1\n");
    }
    if (init_args_wants_weston()) weston_want = 1;

    mkdir_p("/dev", 0755);
    mknode("/dev/null", S_IFCHR | 0666, 1, 3);
    mknode("/dev/console", S_IFCHR | 0600, 5, 1);
    mknode("/dev/kmsg", S_IFCHR | 0600, 1, 11);
    mknode("/dev/uinput", S_IFCHR | 0660, 10, 223);
    g_kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);

    flog("EXEC-OK pid=%d argv0=%s argc=%d", getpid(), argv[0], argc);

    mkdir_p("/proc", 0555);
    if (mount("proc", "/proc", "proc", 0, NULL) != 0 && errno != EBUSY)
        flog("warn mount proc errno=%d (%s)", errno, strerror(errno));
    mkdir_p("/sys", 0555);
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0 && errno != EBUSY)
        flog("warn mount sys errno=%d (%s)", errno, strerror(errno));

    mount_metadata();
    dump_mounts(60);
    dump_dir("/dev", 40);

    load_modules_from_list();
    load_dwc3_chain();
    dump_dir("/sys/class/usb_role", 10);
    dump_dir("/sys/class/typec", 10);
    force_usb_role();
    wait_udc(20); /* v6: 10s，每 2s 重写 role/mode */

    if (mount_arch_erofs("/system/arch-rootfs.erofs", "/system/arch") != 0) {
        flog("EROFS-LOWER failed; rebooting instead of entering an unusable root");
        sync();
        sleep(10);
        reboot(RB_AUTOBOOT);
        for (;;) pause();
    }

    int shell_ok = -1;
    if (setup_gadget() == 0) {
        shell_ok = shell_on_ttygs();
        flog("SHELL-RESULT rc=%d", shell_ok);
    }
    if (shell_ok != 0) flog("gadget: no console shell, will sleep then reboot");


    if (shell_ok != 0) probe_chroot_userspace();   /* v6: 串口已通时跳过 probe，避免 mount 叠加 */

    if (shell_ok == 0) {
        flog("ARCH-SHELL-READY (display OFF by default; use /usr/local/bin/drm_demo manually)");
        /* OLED 保护：默认不点屏、背光保持 0；需要桌面时用 --weston 或 START_WESTON=1 */
        mknod_uinput();
        if (kde_want) {
            start_kde_desktop();
        } else if (weston_want) {
            flog("WESTON: requested, starting after shell");
            start_weston_desktop();
        } else {
            flog("WESTON: not requested（默认黑屏；--weston / START_WESTON=1 才启动）");
        }
        for (;;) {
            sleep(2);
            monitor_weston();
            if (kde_want) {
                int status;
                pid_t child;
                while ((child = waitpid(-1, &status, WNOHANG)) > 0)
                    flog("KDE-CHILD-EXIT pid=%d status=%d", (int)child, status);
            }
        }
    }
    flog("DISPLAY-OFF (auto demo disabled for OLED protection)");
    flog("SLEEP-120 evidence-done");
    if (g_selftest) { flog("SELFTEST-DONE"); _exit(0); }
    sleep(120);
    flog("REBOOT-NOW");
    sync();
    reboot(RB_AUTOBOOT);
    for (;;) pause();
}

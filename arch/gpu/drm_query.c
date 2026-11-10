/* Read-only DRM queries for the K60 Pro. No SET_MASTER, modeset, buffer
 * allocation, client-cap changes, or writes to device/sysfs nodes.
 * Freestanding Linux aarch64: works with Android and Arch without a libc.
 */
typedef unsigned int u32;
typedef unsigned long u64;
typedef long s64;

static s64 sc(s64 nr, s64 a, s64 b, s64 c, s64 d) {
    register s64 x0 __asm__("x0") = a;
    register s64 x1 __asm__("x1") = b;
    register s64 x2 __asm__("x2") = c;
    register s64 x3 __asm__("x3") = d;
    register s64 x8 __asm__("x8") = nr;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x8) : "memory", "cc");
    return x0;
}
static void out(const char *s) {
    u64 n = 0;
    while (s[n]) ++n;
    while (n) {
        s64 r = sc(64, 1, (s64)s, n, 0);
        if (r == -4) continue;
        if (r <= 0) return;
        s += r; n -= r;
    }
}
static void number(s64 n) {
    char b[32]; u64 v; int i = 31; b[i] = 0;
    if (n < 0) { out("-"); v = (u64)(-(n + 1)) + 1; } else v = n;
    do { b[--i] = '0' + v % 10; v /= 10; } while (v);
    out(b + i);
}
static void field(const char *name, s64 value) { out(name); out("="); number(value); out(" "); }
struct version {
    int major, minor, patch, pad;
    u64 name_len, name, date_len, date, desc_len, desc;
};
struct cap { u64 capability, value; };
struct resources {
    u64 fb_ptr, crtc_ptr, connector_ptr, encoder_ptr;
    u32 fbs, crtcs, connectors, encoders;
    u32 min_width, max_width, min_height, max_height;
};
_Static_assert(sizeof(struct version) == 64, "DRM version ABI");
_Static_assert(sizeof(struct resources) == 64, "DRM resources ABI");
_Static_assert(sizeof(struct cap) == 16, "DRM cap ABI");
#define IOWR(n, type) (0xc0000000UL | (sizeof(type) << 16) | (0x64UL << 8) | (n))
static char namebuf[128], datebuf[128], descbuf[256];
static u32 fbids[64], crtcs[64], connectors[64], encoders[64];
static void query(const char *path) {
    out("DEVICE "); out(path); out("\n");
    s64 fd = sc(56, -100, (s64)path, 0x80000, 0); /* O_RDONLY|O_CLOEXEC */
    field("open_rc", fd); out("\n");
    if (fd < 0) return;
    struct version v = {0,0,0,0,127,(u64)namebuf,127,(u64)datebuf,255,(u64)descbuf};
    s64 rc = sc(29, fd, IOWR(0, struct version), (s64)&v, 0);
    out("VERSION "); field("rc",rc); field("major",v.major); field("minor",v.minor);
    out("name="); out(namebuf); out(" desc="); out(descbuf); out("\n");
    const u64 ids[] = {1, 3, 4, 5, 6, 0x10, 0x12, 0x13, 0x14};
    const char *labels[] = {"DUMB_BUFFER", "DUMB_DEPTH", "DUMB_SHADOW", "PRIME", "MONOTONIC", "ADDFB2_MODIFIERS", "CRTC_IN_VBLANK", "SYNCOBJ", "SYNCOBJ_TIMELINE"};
    for (u32 i=0; i<sizeof(ids)/sizeof(ids[0]); ++i) {
        struct cap c = {ids[i], 0};
        rc = sc(29, fd, IOWR(0x0c, struct cap), (s64)&c, 0);
        out("CAP "); out(labels[i]); out(" "); field("rc",rc); field("value",c.value); out("\n");
    }
    struct resources r = {0};
    rc = sc(29, fd, IOWR(0xa0, struct resources), (s64)&r, 0);
    out("RESOURCES "); field("rc",rc); field("crtcs",r.crtcs); field("connectors",r.connectors); field("encoders",r.encoders); field("fbs",r.fbs); out("\n");
    if (rc == 0 && r.fbs <= 64 && r.crtcs <= 64 && r.connectors <= 64 && r.encoders <= 64) {
        r.fb_ptr=(u64)fbids; r.crtc_ptr=(u64)crtcs; r.connector_ptr=(u64)connectors; r.encoder_ptr=(u64)encoders;
        rc = sc(29, fd, IOWR(0xa0, struct resources), (s64)&r, 0);
        out("RESOURCE_IDS "); field("rc",rc);
        for(u32 i=0;i<r.crtcs && i<64;++i) field("crtc",crtcs[i]);
        for(u32 i=0;i<r.connectors && i<64;++i) field("connector",connectors[i]);
        for(u32 i=0;i<r.encoders && i<64;++i) field("encoder",encoders[i]);
        out("\n");
    }
    sc(57, fd, 0, 0, 0);
}
__attribute__((noreturn)) void _start(void) {
    out("DRM-READONLY-QUERY-v1 (negative rc is Linux errno)\n");
    query("/dev/dri/card0");
    out("DRM-READONLY-QUERY-DONE\n");
    sc(93, 0, 0, 0, 0);
    __builtin_unreachable();
}

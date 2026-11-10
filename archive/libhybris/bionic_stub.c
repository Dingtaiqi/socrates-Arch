/* memset_explicit.c — bionic stub: bionic linker loads this as Android lib.
 * Built with -nostdlib so it has no glibc NEEDED. Provides memset_explicit
 * (A17 libbinder needs it) and a few likely-missing newer libc symbols. */
typedef unsigned long size_t;

void *memset_explicit(void *dst, int c, size_t n)
{
    unsigned char *p = (unsigned char *)dst;
    while (n--) *p++ = (unsigned char)c;
    return dst;
}

void *__memset_chk(void *dst, int c, size_t n, size_t dstlen)
{
    (void)dstlen;
    unsigned char *p = (unsigned char *)dst;
    while (n--) *p++ = (unsigned char)c;
    return dst;
}

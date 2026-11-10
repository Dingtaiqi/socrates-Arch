/* shim_exidx.c — 为 libhybris 的 API30 linker 插件 (q.so) 提供 arm64 上缺失的符号 */
#include <unwind.h>
#include <stddef.h>

_Unwind_Ptr android_dl_unwind_find_exidx(_Unwind_Ptr pc, int *pcount)
{
    (void)pc;
    if (pcount) *pcount = 0;
    return 0;
}

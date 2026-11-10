#!/system/bin/sh
# final_test.sh — GPU 用户态最终验证（Arch 内运行；镜像 C 布局）
# 期望输出：EGL-PROBE-OK vendor=... renderer='Adreno740...' pixel_ok=1
set -u

HYB=/opt/hyb4
PATCHED=/opt/bion_patched/patched_bionic
A11=/opt/bion_a11
VENDOR=/vendor/lib64
FW=/opt/fw
LOG=/proc/1/root/metadata/gpu_final.log

exec > "$LOG" 2>&1 || true
echo "=== GPU FINAL TEST $(date) ==="

# 0) 固件 + KGSL
mkdir -p "$FW"
[ -f "$FW/a740_zap.mbn" ]   || cp /proc/1/root/odm/firmware/a740_zap.mbn "$FW/" 2>/dev/null
[ -f "$FW/a740_sqe.fw" ]    || cp /proc/1/root/vendor/firmware/a740_sqe.fw "$FW/" 2>/dev/null
[ -f "$FW/gmu_gen70200.bin" ] || cp /proc/1/root/vendor/firmware/gmu_gen70200.bin "$FW/" 2>/dev/null
echo -n /mnt/opt/fw > /sys/module/firmware_class/parameters/path 2>/dev/null
d=$(cat /sys/class/kgsl/kgsl-3d0/dev 2>/dev/null)
[ -n "$d" ] && mknod /dev/kgsl-3d0 c "${d%:*}" "${d#*:}" 2>/dev/null
if exec 3<>/dev/kgsl-3d0; then echo "KGSL-OPEN-OK"; else echo "KGSL-OPEN-FAIL"; fi

# 1) 环境
unset LD_PRELOAD
export LD_LIBRARY_PATH="$HYB:$PATCHED:$PATCHED/companions:$A11/system64:$A11/system_ext64:$A11/product64:$VENDOR"
export HYBRIS_LINKER_DIR="$HYB"
export HYBRIS_LD_LIBRARY_PATH="$PATCHED:$PATCHED/companions:$A11/system64:$A11/system_ext64:$A11/product64:$VENDOR"
export HYBRIS_EGL_PLATFORM="${HYBRIS_EGL_PLATFORM:-null}"
export HYBRIS_DEBUG=1
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

# 2) 分步验证
echo "--- dlopen_test ---"
/opt/gpu/dlopen_test libEGL_adreno.so eglGetDisplay
echo "DL-RC=$?"

echo "--- egl_probe ---"
/opt/gpu/egl_probe_ub --width 64 --height 64 --frames 3
rc=$?
echo "EGL-RC=$rc"

echo "=== RESULT: KGSL_OPEN_AND_EGL rc=$rc ==="
exit $rc

#!/bin/sh
# Explicit, bounded diagnostic in the existing Arch DSU RAM overlay.
# No boot/partition/DSU metadata writes. Logs must be exported before reboot.
set -eu
[ "$(id -u)" = 0 ]
[ "$(uname -m)" = aarch64 ]
[ -f /etc/arch-release ]
kit=/opt/kde-dsu
icd=$kit/turnip-26.2.6/share/vulkan/icd.d/freedreno_icd.aarch64.json
[ -r "$icd" ]
[ -x "$kit/tools/bin/vulkaninfo" ]
[ -x "$kit/tools/bin/egl_zink_probe" ]
log=/dev/kde_dsu/gpu2
mkdir -p "$log/runtime"
chmod 700 "$log" "$log/runtime"

node_from_sysfs() {
    sysdev=$1
    target=$2
    IFS=: read -r major minor <"$sysdev"
    case "$major:$minor" in *[!0-9:]*|:|*:) return 1;; esac
    if [ -e "$target" ]; then
        [ -c "$target" ]
        [ "$(stat -c '%t:%T' "$target")" = "$(printf '%x:%x' "$major" "$minor")" ]
    else
        mknod -m 600 "$target" c "$major" "$minor"
    fi
}
node_from_sysfs /sys/class/kgsl/kgsl-3d0/dev /dev/kgsl-3d0
mkdir -p /dev/dma_heap
node_from_sysfs /sys/class/dma_heap/system/dev /dev/dma_heap/system

fwparam=/sys/module/firmware_class/parameters/path
if old_fw=$(cat "$fwparam" 2>"$log/firmware-path-read.log"); then
    restore_fw=1
else
    restore_fw=0
    printf 'Prior firmware path unreadable; the required reboot resets this runtime parameter.\n'
fi
trap 'if [ "$restore_fw" = 1 ]; then printf "%s\n" "$old_fw" >"$fwparam"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for firmware in a740_sqe.fw a740_zap.mbn gmu_gen70200.bin; do
    [ -r "/proc/1/root/mnt/opt/fw/$firmware" ]
done
printf '%s\n' /mnt/opt/fw >"$fwparam"
cat "$fwparam" >"$log/firmware-path-after.log" 2>&1 || true
unset LD_PRELOAD HYBRIS_LD_LIBRARY_PATH EGL_PLATFORM DISPLAY WAYLAND_DISPLAY
unset VK_ICD_FILENAMES VK_INSTANCE_LAYERS VK_LAYER_PATH MESA_VK_DEVICE_SELECT
unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
export LD_LIBRARY_PATH="$kit/tools/lib:$kit/turnip-26.2.6/lib"
export VK_DRIVER_FILES="$icd"
export XDG_RUNTIME_DIR="$log/runtime"
export VK_LOADER_DEBUG=error,warn
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
{
    uname -a
    cat /sys/class/kgsl/kgsl-3d0/gpu_model
    ls -l /dev/kgsl-3d0 /dev/dma_heap/system
    sha256sum "$kit/turnip-26.2.6/lib/libvulkan_freedreno.so"
} >"$log/environment.log" 2>&1
dmesg >"$log/dmesg-before.log" 2>&1 || true
set +e
timeout -k 3 40 "$kit/tools/bin/vulkaninfo" --summary >"$log/vulkan-summary.log" 2>&1
vk_rc=$?
env MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink \
    timeout -k 3 40 "$kit/tools/bin/egl_zink_probe" >"$log/egl-zink.log" 2>&1
egl_rc=$?
set -e
dmesg >"$log/dmesg-after.log" 2>&1 || true
printf 'VULKANINFO_RC=%s EGL_ZINK_RC=%s\n' "$vk_rc" "$egl_rc" | tee "$log/results.log"
cat "$log/environment.log" "$log/vulkan-summary.log" "$log/egl-zink.log"
printf 'Logs: %s (export before reboot)\n' "$log"
[ "$vk_rc" -eq 0 ] && [ "$egl_rc" -eq 0 ]

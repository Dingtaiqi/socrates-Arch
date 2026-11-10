#!/system/bin/sh
# setup_vendor.sh — 从宿主 vendor 分区(dm-3)补齐 Adreno EGL 目录与 vendor 闭包
# 真机验证：2026-11-09 07:25 用这套操作拿到 EGL-PROBE-OK renderer='Adreno (TM) 4XX'
# 幂等；失败不致命（会打印 WARN 继续）
set -u
WARN=0
say() { echo "[setup_vendor] $*"; }

# 1) 确保 dm-3 设备节点
if [ ! -e /dev/block/dm-3 ]; then
  mknod -m 600 /dev/block/dm-3 b 254 3 2>/dev/null || true
fi
if [ ! -b /dev/block/dm-3 ]; then
  say "WARN: /dev/block/dm-3 不存在（非 DSU 环境？）"; WARN=1
fi

# 2) 挂载宿主 vendor 分区
mkdir -p /hsysv
if ! grep -q " /hsysv " /proc/mounts 2>/dev/null; then
  mount -t erofs -o ro /dev/block/dm-3 /hsysv 2>/dev/null || \
  mount -t f2fs -o ro /dev/block/dm-3 /hsysv 2>/dev/null || \
  mount -o ro /dev/block/dm-3 /hsysv 2>/dev/null || true
fi

if [ -d /hsysv/lib64/egl ]; then
  # 3) EGL 子驱动全套（关键：eglSubDriverAndroid.so）
  mkdir -p /vendor/lib64/egl
  cp -a /hsysv/lib64/egl/. /vendor/lib64/egl/ 2>/dev/null
  say "egl files: $(ls /vendor/lib64/egl | wc -l)"

  # 4) vendor 闭包（36 -> ~340）
  for f in /hsysv/lib64/vendor.*.so /hsysv/lib64/libgralloc*.so /hsysv/lib64/libvmmem*.so \
           /hsysv/lib64/libqspmhal*.so /hsysv/lib64/libqti*.so /hsysv/lib64/libgsl*.so \
           /hsysv/lib64/libCB*.so /hsysv/lib64/libllvm*.so /hsysv/lib64/libdmabuf*.so \
           /hsysv/lib64/libdisplay*.so; do
    [ -e "$f" ] && cp -an "$f" /vendor/lib64/ 2>/dev/null
  done
  say "vendor lib64 count: $(ls /vendor/lib64 | wc -l)"
else
  say "WARN: /hsysv/lib64/egl 不存在，vendor 未补齐"; WARN=1
fi

# 5) hybris 插件目录（编译前缀 /usr）
mkdir -p /usr/lib/libhybris
for f in /opt/hyb4/*.so*; do
  [ -e "$f" ] && ln -sf "$f" "/usr/lib/libhybris/$(basename "$f")" 2>/dev/null
done
say "hybris plugins: $(ls /usr/lib/libhybris 2>/dev/null | wc -l)"

# 6) KGSL 固件路径（已有则跳过）
mkdir -p /opt/fw
[ -f /opt/fw/a740_zap.mbn ]    || cp /proc/1/root/odm/firmware/a740_zap.mbn /opt/fw/ 2>/dev/null
[ -f /opt/fw/a740_sqe.fw ]     || cp /proc/1/root/vendor/firmware/a740_sqe.fw /opt/fw/ 2>/dev/null
[ -f /opt/fw/gmu_gen70200.bin ]|| cp /proc/1/root/vendor/firmware/gmu_gen70200.bin /opt/fw/ 2>/dev/null
[ -f /opt/fw/a740_zap.mbn ] && echo -n /mnt/opt/fw > /sys/module/firmware_class/parameters/path 2>/dev/null

[ "$WARN" -eq 0 ] && say "OK" || say "DONE-WITH-WARNINGS"
exit 0

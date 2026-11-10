#!/bin/bash
# _build_gpu_c13v7.sh — C13v7 = C13v6 + net_up v3 / clock_sync v2（HTTP Date 兜底）
set -uo pipefail
D=/build/arch/native
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13v6.img
OUT=$D/gpu_c13v7.img
PATCH=$D/gpu_c13v7_vs_c13v6.patch
PATCH_W=$D/gpu_c13v7_vs_weston_base.patch
MNT=/mnt/gpu_c13v7_img
LOG=/home/qinghuo/gpu-c13v7-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v7 (http date) $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 1) net_up.sh v3 + clock_sync.sh v2 ---"
cp -f /tmp/net_up_v3.sh "$R/opt/gpu/net_up.sh"; chmod 755 "$R/opt/gpu/net_up.sh"
cp -f /tmp/clock_sync_v2.sh "$R/opt/gpu/clock_sync.sh"; chmod 755 "$R/opt/gpu/clock_sync.sh"
sha256sum "$R/opt/gpu/net_up.sh" "$R/opt/gpu/clock_sync.sh"
echo "--- 关键行 ---"
grep -nE "192\.168\.137|baidu|generate_204|CLOCK-SYNC-OK|NET-UP-OK" "$R/opt/gpu/net_up.sh" "$R/opt/gpu/clock_sync.sh" | head -12
echo "--- 2) 保持 C13v6 验证点 ---"
echo "init=$(sha256sum "$MNT/system/bin/init" | awk '{print $1}') ncm=$(strings "$MNT/system/bin/init" | grep -c ncm)"
echo "libEGL marker=$(strings "$R/opt/hyb4/libEGL.so.1.0.0" | grep -c EGL_MESA_platform_surfaceless)"
echo "--- 3) 空间/卸载 ---"
sync; DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 4) fsck ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v7_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v7_fsck.log
echo "--- 5) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
NET_SHA=$(sha256sum /tmp/net_up_v3.sh | awk '{print $1}'); CLK_SHA=$(sha256sum /tmp/clock_sync_v2.sh | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "net_up=/opt/gpu/net_up.sh sha256=$NET_SHA size=$(stat -c%s /tmp/net_up_v3.sh)";
  echo "clock_sync=/opt/gpu/clock_sync.sh sha256=$CLK_SHA size=$(stat -c%s /tmp/clock_sync_v2.sh)";
  echo "clock_chain=RTC(since_epoch>1.7e9) -> hwclock -> HTTP Date (baidu/miui generate_204)";
  echo "init=minit_v19 acm+ncm; libEGL=hyb4sfnw; final_test=v4";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=sh /opt/gpu/net_up.sh; sh /opt/gpu/clock_sync.sh; date; pacman -Sy";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 6) patch ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH" || echo WARN
python3 /build/arch/native/gen_block_diff.py "$D/weston_base.img" "$OUT" "$PATCH_W" || echo WARN
ls -la "$PATCH" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH" "$PATCH_W" 2>/dev/null | tee /tmp/c13v7_patch.sha
echo "--- 7) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key; J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v7" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" /tmp/c13v7_patch.sha /tmp/net_up_v3.sh /tmp/clock_sync_v2.sh $J:/root/gpu_c13v7/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v7 && ls -la && sha256sum gpu_c13v7.img.gz gpu_c13v7_vs_c13v6.patch net_up_v3.sh clock_sync_v2.sh 2>/dev/null" 2>&1 | tail -14
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" "$PATCH_W" /tmp/c13v7_patch.sha /tmp/net_up_v3.sh /tmp/clock_sync_v2.sh "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

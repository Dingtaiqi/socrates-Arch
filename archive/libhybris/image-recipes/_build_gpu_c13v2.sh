#!/bin/bash
# _build_gpu_c13v2.sh — C13v2：C13 + hyb4z 叠加 + /usr/lib/libhybris symlink + setup_vendor.sh + final_test v2 + weston_gpu_test.sh
# 保持 1.5GiB；产出 img/gz + patch vs gpu_c13（小）+ patch vs weston_base
set -uo pipefail
D=/build/arch/native
G=/build/arch/gpu
IC=$G/image_c
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13.img
WBASE=$D/weston_base.img
OUT=$D/gpu_c13v2.img
PATCH_C13=$D/gpu_c13v2_vs_c13.patch
PATCH_W=$D/gpu_c13v2_vs_weston_base.patch
MNT=/mnt/gpu_c13v2_img
LOG=/home/qinghuo/gpu-c13v2-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v2 $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
[ -d "$IC/hyb4z" ] || { echo FATAL hyb4z; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 1) hyb4z 叠加覆盖 /opt/hyb4 ---"
echo "before: $(ls "$R/opt/hyb4" | wc -l) files"
cp -a "$IC/hyb4z/." "$R/opt/hyb4/" 2>/dev/null || true
echo "after : $(ls "$R/opt/hyb4" | wc -l) files, plugins: $(ls "$R/opt/hyb4/libhybris" 2>/dev/null | wc -l)"
echo "--- 2) /usr/lib/libhybris 符号链接 ---"
mkdir -p "$R/usr/lib/libhybris"
for f in "$R"/opt/hyb4/*.so*; do
  [ -e "$f" ] && ln -sf "$f" "$R/usr/lib/libhybris/$(basename "$f")"
done
echo "usr/lib/libhybris: $(ls "$R/usr/lib/libhybris" | wc -l) links; eglplatform_null=$(readlink -f "$R/usr/lib/libhybris/eglplatform_null.so" 2>/dev/null)"
echo "--- 3) /opt/gpu 脚本（setup_vendor/final_test v2/weston_gpu_test） ---"
cp -f /tmp/setup_vendor.sh "$R/opt/gpu/setup_vendor.sh"
cp -f /tmp/final_test_v2.sh "$R/opt/gpu/final_test.sh"
cp -f /tmp/weston_gpu_test.sh "$R/opt/gpu/weston_gpu_test.sh"
chmod 755 "$R/opt/gpu/"*.sh
ls -la "$R/opt/gpu"
echo "--- 4) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 5) fsck + 校验 ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v2_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v2_fsck.log
debugfs -R 'stat /system/arch/opt/hyb4/libEGL.so.1.0.0' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/hyb4/libhybris/q.so' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/gpu/setup_vendor.sh' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/gpu/final_test.sh' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/gpu/weston_gpu_test.sh' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/usr/lib/libhybris/eglplatform_null.so' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
echo "--- 6) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "hyb4z=$(sha256sum "$IC/hyb4z.tar.gz" | awk '{print $1}')";
  echo "scripts=setup_vendor.sh(final_test_v2/weston_gpu_test)";
  echo "vendor=运行时 dm-3 补齐（setup_vendor.sh），镜像内 vendor=36+2";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=串口: bash /opt/gpu/final_test.sh ；之后 bash /opt/gpu/weston_gpu_test.sh";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 7) patches ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH_C13" || echo "WARN diff c13"
python3 /build/arch/native/gen_block_diff.py "$WBASE" "$OUT" "$PATCH_W" || echo "WARN diff weston_base"
ls -la "$PATCH_C13" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH_C13" "$PATCH_W" 2>/dev/null | tee /tmp/c13v2_patch.sha
echo "--- 8) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key
J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v2" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13" "$PATCH_W" /tmp/c13v2_patch.sha $J:/root/gpu_c13v2/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v2 && ls -la && sha256sum gpu_c13v2.img.gz gpu_c13v2_vs_c13.patch 2>/dev/null" 2>&1 | tail -12
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13" "$PATCH_W" /tmp/c13v2_patch.sha "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

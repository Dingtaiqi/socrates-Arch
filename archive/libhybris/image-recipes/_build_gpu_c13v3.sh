#!/bin/bash
# _build_gpu_c13v3.sh — C13v3：C13v2 + Lead 的 full vendor bundle（352 libs/140MB）baked 进 /vendor
set -uo pipefail
D=/build/arch/native
G=/build/arch/gpu
V=$G/vendor_packs
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13v2.img
OUT=$D/gpu_c13v3.img
PATCH_C13V2=$D/gpu_c13v3_vs_c13v2.patch
PATCH_W=$D/gpu_c13v3_vs_weston_base.patch
MNT=/mnt/gpu_c13v3_img
LOG=/home/qinghuo/gpu-c13v3-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v3 $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
[ -d "$V/full/c13v2_vendor/vendor/lib64" ] || { echo FATAL vendor bundle; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 1) bake full vendor bundle → /vendor ---"
mkdir -p "$R/vendor/lib64/egl" "$R/vendor/lib64/hw"
cp -a "$V/full/c13v2_vendor/vendor/lib64/egl/." "$R/vendor/lib64/egl/" 2>/dev/null || true
cp -a "$V/full/c13v2_vendor/vendor/lib64/hw/." "$R/vendor/lib64/hw/" 2>/dev/null || true
for f in "$V/full/c13v2_vendor/vendor/lib64"/*.so; do [ -e "$f" ] && cp -a "$f" "$R/vendor/lib64/"; done
cp -f "$V/full/c13v2_vendor/install_vendor_offline.sh" "$R/opt/gpu/install_vendor_offline.sh" 2>/dev/null || true
cp -f "$V/full/c13v2_vendor/MANIFEST.txt" "$R/opt/gpu/vendor_MANIFEST.txt" 2>/dev/null || true
chmod 755 "$R/opt/gpu/install_vendor_offline.sh" 2>/dev/null || true
echo "vendor baked: $(ls "$R/vendor/lib64"/*.so 2>/dev/null | wc -l) libs, egl $(ls "$R/vendor/lib64/egl" 2>/dev/null | wc -l), hw $(ls "$R/vendor/lib64/hw" 2>/dev/null | wc -l)"
echo "--- 2) 关键文件核对 ---"
for f in libEGL_adreno.so libGLESv2_adreno.so libgsl.so libCB.so libllvm-glnext.so libgralloc.qti.so libgralloccore.so libgrallocutils.so libadreno_utils.so; do
  [ -e "$R/vendor/lib64/$f" ] && echo "  [ok] $f $(stat -c%s "$R/vendor/lib64/$f")B" || echo "  [MISS] $f"
done
for f in eglSubDriverAndroid.so libGLESv2_adreno.so libEGL_adreno.so libq3dtools_esx.so; do
  [ -e "$R/vendor/lib64/egl/$f" ] && echo "  [ok] egl/$f $(stat -c%s "$R/vendor/lib64/egl/$f")B" || echo "  [MISS] egl/$f"
done
echo "--- 3) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 4) fsck ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v3_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v3_fsck.log
echo "--- 5) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "vendor_bundle=c13v2_vendor.tar.gz sha=$(sha256sum "$V/c13v2_vendor.tar.gz" | awk '{print $1}')";
  echo "vendor_files=$(ls "$V/full/c13v2_vendor/vendor/lib64"/*.so 2>/dev/null | wc -l)+egl7+hw";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=串口: bash /opt/gpu/final_test.sh（setup_vendor 会检测已 baked 并快速跳过）";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 6) patches ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH_C13V2" || echo "WARN diff c13v2"
python3 /build/arch/native/gen_block_diff.py "$D/weston_base.img" "$OUT" "$PATCH_W" || echo "WARN diff weston_base"
ls -la "$PATCH_C13V2" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH_C13V2" "$PATCH_W" 2>/dev/null | tee /tmp/c13v3_patch.sha
echo "--- 7) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key
J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v3" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13V2" /tmp/c13v3_patch.sha $J:/root/gpu_c13v3/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v3 && ls -la && sha256sum gpu_c13v3.img.gz 2>/dev/null" 2>&1 | tail -10
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13V2" "$PATCH_W" /tmp/c13v3_patch.sha "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

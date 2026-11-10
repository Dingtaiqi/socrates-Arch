#!/bin/bash
# _build_gpu_c13v4.sh — C13v4 = C13v3 + hyb4sfnw 7 件覆盖 /opt/hyb4 + final_test v4(dmabuf probe)
set -uo pipefail
D=/build/arch/native
G=/build/arch/gpu
S=$G/hyb4sfnw
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13v3.img
OUT=$D/gpu_c13v4.img
PATCH=$D/gpu_c13v4_vs_c13v3.patch
PATCH_W=$D/gpu_c13v4_vs_weston_base.patch
MNT=/mnt/gpu_c13v4_img
LOG=/home/qinghuo/gpu-c13v4-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v4 $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
[ -d "$S/out" ] || { echo FATAL nw out; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 1) 覆盖 /opt/hyb4（hyb4sfnw 7 件） ---"
cp -a "$S/out/." "$R/opt/hyb4/" 2>/dev/null || true
# 确保 symlink 链正确：libEGL.so -> libEGL.so.1 -> libEGL.so.1.0.0
( cd "$R/opt/hyb4" && ln -sf libEGL.so.1.0.0 libEGL.so.1 && ln -sf libEGL.so.1.0.0 libEGL.so ) 2>/dev/null || true
ls -la "$R/opt/hyb4" | grep -E "libEGL|eglplatform|platformcommon" 
echo "marker=$(strings "$R/opt/hyb4/libEGL.so.1.0.0" | grep -c EGL_MESA_platform_surfaceless) wayland_ext=$(strings "$R/opt/hyb4/libEGL.so.1.0.0" | grep -c EGL_EXT_platform_wayland)"
echo "--- 2) 重建 /usr/lib/libhybris 符号链接（指向 /opt/hyb4/<name>） ---"
rm -rf "$R/usr/lib/libhybris"; mkdir -p "$R/usr/lib/libhybris"
n=0
for f in "$R"/opt/hyb4/*.so*; do [ -e "$f" ] || continue; b=$(basename "$f"); ln -sf "/opt/hyb4/$b" "$R/usr/lib/libhybris/$b"; n=$((n+1)); done
echo "symlinks=$n; eglplatform_null -> $(readlink "$R/usr/lib/libhybris/eglplatform_null.so")"
echo "--- 3) final_test v4 ---"
cp -f /tmp/final_test_v4.sh "$R/opt/gpu/final_test.sh"
chmod 755 "$R/opt/gpu/final_test.sh"; sha256sum "$R/opt/gpu/final_test.sh"
echo "--- 4) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 5) fsck + verify ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v4_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v4_fsck.log
debugfs -R 'stat /system/arch/opt/hyb4/libEGL.so.1.0.0' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/hyb4/libhybris-eglplatformcommon.so.1.0.0' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
echo "--- 6) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "nw_bundle=hyb4sfnw.tar.gz sha=$(sha256sum "$S/hyb4sfnw.tar.gz" | awk '{print $1}')";
  echo "libEGL_sha=$(sha256sum "$S/out/libEGL.so.1.0.0" | awk '{print $1}') size=$(stat -c%s "$S/out/libEGL.so.1.0.0")";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=串口: bash /opt/gpu/final_test.sh ；之后 bash /opt/gpu/weston_gpu_test.sh";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 7) patch vs C13v3 ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH" || echo WARN
python3 /build/arch/native/gen_block_diff.py "$D/weston_base.img" "$OUT" "$PATCH_W" || echo WARN
ls -la "$PATCH" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH" "$PATCH_W" 2>/dev/null | tee /tmp/c13v4_patch.sha
echo "--- 8) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key; J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v4" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" /tmp/c13v4_patch.sha $J:/root/gpu_c13v4/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v4 && ls -la && sha256sum gpu_c13v4.img.gz gpu_c13v4_vs_c13v3.patch 2>/dev/null" 2>&1 | tail -12
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" "$PATCH_W" /tmp/c13v4_patch.sha "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

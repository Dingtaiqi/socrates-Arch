#!/bin/bash
# _build_gpu_c13v3fix.sh — C13v3：C13v2 + 修复 /usr/lib/libhybris symlink 目标 + final_test tee/GLIBC_TUNABLES
set -uo pipefail
D=/build/arch/native
IC=/build/arch/gpu/image_c
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13v2.img
OUT=$D/gpu_c13v3.img
PATCH_C13V2=$D/gpu_c13v3_vs_c13v2.patch
PATCH_W=$D/gpu_c13v3_vs_weston_base.patch
MNT=/mnt/gpu_c13v3f_img
LOG=/home/qinghuo/gpu-c13v3fix-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v3(fix) $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 1) 修复 /usr/lib/libhybris symlink 目标（指向镜像内 /opt/hyb4/<name>） ---"
rm -rf "$R/usr/lib/libhybris"; mkdir -p "$R/usr/lib/libhybris"
n=0
for f in "$R"/opt/hyb4/*.so*; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  ln -sf "/opt/hyb4/$b" "$R/usr/lib/libhybris/$b"
  n=$((n+1))
done
echo "created $n symlinks; samples:"
ls -la "$R/usr/lib/libhybris" | head -8
readlink "$R/usr/lib/libhybris/eglplatform_null.so"
readlink "$R/usr/lib/libhybris/libEGL.so.1"
echo "--- 2) 更新 final_test.sh（tee→>>、GLIBC_TUNABLES） ---"
cp -f /tmp/final_test_v3.sh "$R/opt/gpu/final_test.sh"
chmod 755 "$R/opt/gpu/final_test.sh"
sha256sum "$R/opt/gpu/final_test.sh"
echo "--- 3) 同时把 setup_vendor.sh 内 symlink 逻辑核对（运行时用 /opt/hyb4 绝对路径） ---"
grep -n "ln -sf" "$R/opt/gpu/setup_vendor.sh" 2>/dev/null | head -3
echo "--- 4) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 5) fsck + 校验 ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v3f_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v3f_fsck.log
echo "--- 6) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "fixes=symlink-target(/opt/hyb4/...) + final_test no-tee + GLIBC_TUNABLES";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=串口: bash /opt/gpu/final_test.sh";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 7) patches ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH_C13V2" || echo "WARN diff c13v2"
python3 /build/arch/native/gen_block_diff.py "$D/weston_base.img" "$OUT" "$PATCH_W" || echo "WARN diff weston_base"
ls -la "$PATCH_C13V2" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH_C13V2" "$PATCH_W" 2>/dev/null | tee /tmp/c13v3f_patch.sha
echo "--- 8) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key
J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v3" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13V2" /tmp/c13v3f_patch.sha $J:/root/gpu_c13v3/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v3 && ls -la && sha256sum gpu_c13v3.img.gz gpu_c13v3_vs_c13v2.patch 2>/dev/null" 2>&1 | tail -12
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH_C13V2" "$PATCH_W" /tmp/c13v3f_patch.sha "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

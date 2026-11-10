#!/bin/bash
# _build_gpu_c13.sh — 镜像 C13（Halium13 A13-patched bionic + A13 system 全量 + hyb4 + Adreno blob + 固件 + 工具）
set -uo pipefail
D=/build/arch/native
G=/build/arch/gpu
IC=$G/image_c
H13=$G/halium13
E=/home/qinghuo/arch_export
BASE=$D/weston_base.img
OUT=$D/gpu_c13.img
PATCH=$D/gpu_c13_vs_weston_base.patch
MNT=/mnt/gpu_c13_img
LOG=/home/qinghuo/gpu-c13-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13 $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
[ -d "$IC/hyb4" ] || { echo FATAL hyb4; exit 1; }
[ -f "$H13/bionic_real/libc.so" ] || { echo FATAL patched libc; exit 1; }
[ -d "$H13/system64" ] || { echo FATAL a13 system64; exit 1; }
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 0) init 保持 base（minit v18），init.args 无 --weston ---"
ARGS='--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60'
mkdir -p "$MNT/system/etc/arch"
printf '%s\n' "$ARGS" > "$MNT/system/etc/arch/init.args"
printf '%s\n' "$ARGS" > "$MNT/system/arch/init.args"
echo "--- 1) /opt/hyb4 ---"
rm -rf "$R/opt/hyb4"; mkdir -p "$R/opt/hyb4/libhybris"
cp -f "$IC"/hyb4/*.so* "$R/opt/hyb4/" 2>/dev/null || true
for p in mm n o q; do cp -f "$IC/hyb4/$p.so" "$R/opt/hyb4/libhybris/$p.so" 2>/dev/null || true; done
echo "hyb4=$(ls "$R/opt/hyb4" | wc -l) plugins=$(ls "$R/opt/hyb4/libhybris" | wc -l)"
echo "--- 2) /opt/bion_patched/patched_bionic（核心 4：libc/libm/libdl/libdl_android） ---"
rm -rf "$R/opt/bion_patched"; mkdir -p "$R/opt/bion_patched/patched_bionic"
for n in libc.so libm.so libdl.so libdl_android.so; do cp -f "$H13/bionic_real/$n" "$R/opt/bion_patched/patched_bionic/" 2>/dev/null || true; done
ls -la "$R/opt/bion_patched/patched_bionic"
echo "--- 3) /opt/bion_a13/{system64,system_ext64,product64}（A13 全量 151MB + ld-android） ---"
rm -rf "$R/opt/bion_a13"
for part in system64 system_ext64 product64; do mkdir -p "$R/opt/bion_a13/$part"; done
cp -a "$H13/system64/." "$R/opt/bion_a13/system64/" 2>/dev/null || true
# 补 ld-android.so（A13 runtime apex 里）
[ -f "$H13/runtime_lib64/ld-android.so" ] && cp -f "$H13/runtime_lib64/ld-android.so" "$R/opt/bion_a13/system64/"
[ -f "$H13/runtime_lib64/libc++.so" ] && cp -f "$H13/runtime_lib64/libc++.so" "$R/opt/bion_a13/system64/" 2>/dev/null || true
echo "bion_a13: system64=$(ls "$R/opt/bion_a13/system64" | wc -l) ($(du -sh "$R/opt/bion_a13/system64" 2>/dev/null | awk "{print \$1}")); ld-android=$(stat -c%s "$R/opt/bion_a13/system64/ld-android.so" 2>/dev/null)B"
echo "  libc++.so=$(stat -c%s "$R/opt/bion_a13/system64/libc++.so" 2>/dev/null)B libstdc++.so=$(stat -c%s "$R/opt/bion_a13/system64/libstdc++.so" 2>/dev/null)B"
echo "--- 4) /vendor/lib64(+hw) ← gpu_blobs ---"
mkdir -p "$R/vendor/lib64/hw"
cp -L "$G/blobs"/vendor64/*.so "$R/vendor/lib64/" 2>/dev/null || true
cp -L "$G/blobs"/vendorhw/*.so "$R/vendor/lib64/hw/" 2>/dev/null || true
echo "vendor=$(ls "$R/vendor/lib64"/*.so 2>/dev/null | wc -l) hw=$(ls "$R/vendor/lib64/hw" 2>/dev/null | wc -l)"
echo "--- 5) 固件 ---"
mkdir -p "$R/opt/fw" "$R/lib/firmware"
for f in a740_zap.mbn a740_sqe.fw gmu_gen70200.bin; do
  cp -f "$G/blobs/$f" "$R/opt/fw/" 2>/dev/null || true
  cp -f "$G/blobs/$f" "$R/lib/firmware/" 2>/dev/null || true
done
ls -la "$R/opt/fw"
echo "--- 6) /opt/gpu 工具 ---"
mkdir -p "$R/opt/gpu"
for f in egl_probe_ub dlopen_test prop_area_probe libcrashdump2.so final_test.sh; do
  [ -f "$IC/tools/$f" ] && cp -f "$IC/tools/$f" "$R/opt/gpu/"
done
chmod 755 "$R/opt/gpu/"* 2>/dev/null || true
ls -la "$R/opt/gpu"
echo "--- 7) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 8) fsck + 校验 ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13_fsck.log
debugfs -R 'stat /system/bin/init' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/bion_patched/patched_bionic/libc.so' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/bion_a13/system64/libc++.so' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/hyb4/q.so' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/gpu/egl_probe_ub' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/fw/a740_zap.mbn' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'cat /system/etc/arch/init.args' "$OUT" 2>/dev/null
echo "--- 9) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "bion_source=Halium13 webOS-ports/halium-lunes-20260826 (system.img sha $(sha256sum "$H13/halium13.tar.bz2" 2>/dev/null | awk "{print \$1}"))";
  echo "patched_libc_sha=$(sha256sum "$H13/bionic_real/libc.so" | awk "{print \$1}") size=$(stat -c%s "$H13/bionic_real/libc.so")";
  echo "a13_libcxx_sha=$(sha256sum "$H13/system64/libc++.so" | awk "{print \$1}") size=$(stat -c%s "$H13/system64/libc++.so")";
  echo "init_args=$ARGS";
  echo "verify=串口: bash /opt/gpu/final_test.sh";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 10) vs weston_base patch ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH" || echo "WARN diff fail"
[ -f "$PATCH" ] && { ls -la "$PATCH"; sha256sum "$PATCH" | tee "$PATCH.sha256"; }
echo "--- 11) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key
J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" "$PATCH.sha256" $J:/root/gpu_c13/ 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13 && ls -la && sha256sum gpu_c13.img.gz" 2>&1 | tail -10
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" "$PATCH.sha256" "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

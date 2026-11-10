#!/bin/bash
# _build_gpu_c13v5.sh — C13v5 = C13v4 + minit v19(acm+ncm 双功能) + /opt/gpu/net_up.sh
set -uo pipefail
D=/build/arch/native
G=/build/arch/gpu
E=/home/qinghuo/arch_export
BASE=$D/gpu_c13v4.img
OUT=$D/gpu_c13v5.img
PATCH=$D/gpu_c13v5_vs_c13v4.patch
PATCH_W=$D/gpu_c13v5_vs_weston_base.patch
MNT=/mnt/gpu_c13v5_img
LOG=/home/qinghuo/gpu-c13v5-build.log
exec > >(tee -a "$LOG") 2>&1
echo "===== BUILD GPU IMAGE C13v5 (USB-NCM) $(date '+%F %T') ====="
[ -f "$BASE" ] || { echo FATAL base; exit 1; }
echo "--- 1) minit 源码打 NCM 补丁 ---"
cp -f "$D/minit_v18_1_fixed.c" "$D/minit_v19_ncm.c"
python3 - "$D/minit_v19_ncm.c" <<"PYEOF"
import sys
p = sys.argv[1]
src = open(p).read()
if "functions/ncm.0" in src:
    print("already patched")
else:
    anchor = '    rc = symlink("/sys/kernel/config/usb_gadget/arch/functions/acm.gs0", p);\n    flog("gadget: symlink acm.gs0 rc=%d errno=%d", rc, errno);\n'
    add = anchor + '''
    /* v19: USB NCM 网络功能（与 acm 同 config，开机即可用） */
    snprintf(p, sizeof(p), "%s/functions/ncm.0", gd);
    rc = mkdir(p, 0755);
    flog("gadget: mkdir functions/ncm.0 rc=%d errno=%d", rc, errno);
    snprintf(p, sizeof(p), "%s/functions/ncm.0/dev_addr", gd);
    rc = write_file(p, "02:11:22:33:44:55");
    flog("gadget: write ncm dev_addr rc=%d errno=%d", rc, errno);
    snprintf(p, sizeof(p), "%s/configs/c.1/ncm.0", gd);
    rc = symlink("/sys/kernel/config/usb_gadget/arch/functions/ncm.0", p);
    flog("gadget: symlink ncm.0 rc=%d errno=%d", rc, errno);
'''
    if anchor not in src:
        print("ANCHOR NOT FOUND"); sys.exit(1)
    src = src.replace(anchor, add, 1)
    open(p, "w").write(src)
    print("PATCHED minit v19 (ncm)")
PYEOF
echo "ncm markers=$(grep -c "functions/ncm.0" "$D/minit_v19_ncm.c")"
echo "--- 2) 编译 native_init v19（aarch64 static） ---"
aarch64-linux-gnu-gcc -O2 -static -Wall -Wextra -o "$D/minit_v19" "$D/minit_v19_ncm.c" 2> "$D/minit_v19_build.log"
echo "compile_rc=$?"
tail -5 "$D/minit_v19_build.log" 2>/dev/null
ls -la "$D/minit_v19"; file "$D/minit_v19"
sha256sum "$D/minit_v19"
echo "init strings ncm=$(strings "$D/minit_v19" | grep -c ncm) acm=$(strings "$D/minit_v19" | grep -c acm)"
echo "--- 3) 制作 net_up.sh ---"
cp -f /tmp/net_up.sh /tmp/net_up_stage.sh
chmod 755 /tmp/net_up_stage.sh
sha256sum /tmp/net_up_stage.sh
echo "--- 4) 建镜像 ---"
umount "$MNT" 2>/dev/null || true
rm -f "$OUT"; cp -f "$BASE" "$OUT" || exit 1
mkdir -p "$MNT"; mount -o loop,rw "$OUT" "$MNT" || exit 1
R="$MNT/system/arch"
echo "--- 4a) 替换 init（/system/bin/init + /native_init 双份） ---"
cp -f "$D/minit_v19" "$MNT/system/bin/init"; chmod 755 "$MNT/system/bin/init"
cp -f "$D/minit_v19" "$MNT/native_init"; chmod 755 "$MNT/native_init"
ls -la "$MNT/system/bin/init" "$MNT/native_init"
sha256sum "$MNT/system/bin/init" "$MNT/native_init"
echo "image init strings: ncm=$(strings "$MNT/system/bin/init" | grep -c ncm) acm=$(strings "$MNT/system/bin/init" | grep -c acm)"
echo "--- 4b) 安装 /opt/gpu/net_up.sh ---"
cp -f /tmp/net_up_stage.sh "$R/opt/gpu/net_up.sh"; chmod 755 "$R/opt/gpu/net_up.sh"
ls -la "$R/opt/gpu/net_up.sh"; sha256sum "$R/opt/gpu/net_up.sh"
echo "--- 4c) 保留验证：libEGL marker / final_test v4 ---"
echo "libEGL marker=$(strings "$R/opt/hyb4/libEGL.so.1.0.0" | grep -c EGL_MESA_platform_surfaceless) wayland_ext=$(strings "$R/opt/hyb4/libEGL.so.1.0.0" | grep -c EGL_EXT_platform_wayland)"
sha256sum "$R/opt/gpu/final_test.sh"
echo "--- 4d) 空间/卸载 ---"
sync
DFT=$(df -B1 --output=avail "$MNT" | tail -1); echo "image_free_bytes=$DFT"
umount "$MNT" || exit 1
echo "--- 5) fsck ---"
e2fsck -f -y "$OUT" >/tmp/gpu_c13v5_fsck.log 2>&1; echo "e2fsck_rc=$?"; tail -2 /tmp/gpu_c13v5_fsck.log
debugfs -R 'stat /system/bin/init' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /native_init' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
debugfs -R 'stat /system/arch/opt/gpu/net_up.sh' "$OUT" 2>/dev/null | grep -E 'Size:|Mode:'
echo "--- 6) gz + sha ---"
gzip -1 -k -f "$OUT"; gzip -t "$OUT.gz" && echo gzip_test=OK
RAW_SZ=$(stat -c %s "$OUT"); GZ_SZ=$(stat -c %s "$OUT.gz")
RAW_SHA=$(sha256sum "$OUT" | awk '{print $1}'); GZ_SHA=$(sha256sum "$OUT.gz" | awk '{print $1}')
INIT_SHA=$(sha256sum "$D/minit_v19" | awk '{print $1}')
{ echo "img=$(basename "$OUT")"; echo "size=$RAW_SZ"; echo "sha256=$RAW_SHA"; echo "gz_size=$GZ_SZ"; echo "gz_sha256=$GZ_SHA";
  echo "base=$(basename "$BASE") sha256=$(sha256sum "$BASE" | awk '{print $1}')";
  echo "init=minit_v19 size=$(stat -c%s "$D/minit_v19") sha256=$INIT_SHA (acm+ncm)";
  echo "net_up=/opt/gpu/net_up.sh sha256=$(sha256sum /tmp/net_up_stage.sh | awk '{print $1}') size=$(stat -c%s /tmp/net_up_stage.sh)";
  echo "init_args=--rootfs /system/arch --mode shell --gadget acm --console auto --remount-rw --reboot-on-fail 60";
  echo "verify=串口: bash /opt/gpu/final_test.sh; bash /opt/gpu/weston_gpu_test.sh; sh /opt/gpu/net_up.sh; dmesg|grep -i ncm; ls /sys/class/net";
  echo "built_at=$(date -u +%FT%TZ)"; } | tee "$OUT.info"
sha256sum "$OUT" > "$OUT.sha256"; sha256sum "$OUT.gz" > "$OUT.gz.sha256"
echo "--- 7) patch vs C13v4 + vs weston_base ---"
python3 /build/arch/native/gen_block_diff.py "$BASE" "$OUT" "$PATCH" || echo WARN
python3 /build/arch/native/gen_block_diff.py "$D/weston_base.img" "$OUT" "$PATCH_W" || echo WARN
ls -la "$PATCH" "$PATCH_W" 2>/dev/null
sha256sum "$PATCH" "$PATCH_W" 2>/dev/null | tee /tmp/c13v5_patch.sha
echo "--- 8) push jump + export ---"
KEY=/home/qinghuo/.ssh/relay_key; J=root@39.106.175.71
SSHOPT="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=publickey -o BatchMode=yes"
ssh -T $SSHOPT $J "mkdir -p /root/gpu_c13v5" >/dev/null 2>&1 || true
scp -q $SSHOPT "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" /tmp/c13v5_patch.sha "$D/minit_v19" "$D/minit_v19_ncm.c" "$J:/root/gpu_c13v5/" 2>&1 | tail -3
ssh -T $SSHOPT $J "cd /root/gpu_c13v5 && ls -la && sha256sum gpu_c13v5.img.gz gpu_c13v5_vs_c13v4.patch minit_v19 2>/dev/null" 2>&1 | tail -14
cp -f "$OUT" "$OUT.gz" "$OUT.sha256" "$OUT.gz.sha256" "$OUT.info" "$PATCH" "$PATCH_W" /tmp/c13v5_patch.sha "$D/minit_v19" "$D/minit_v19_ncm.c" "$E/" 2>/dev/null || true
chown -R qinghuo:qinghuo "$E"
df -h / | tail -1
echo "===== DONE $(date '+%F %T') ====="

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
# 1) 编译静态探针
aarch64-linux-gnu-gcc -O2 -static -o /build/out/diag_probe /home/qinghuo/diag_probe.c
ls -la /build/out/diag_probe
file /build/out/diag_probe | head -1

# 2) 构建 hostpol6
SRC=/build/out/evox_socrates_system_hostpol5.img
IMG=/build/out/evox_socrates_system_hostpol6.img
MNT=/mnt/hp6
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 2a) 探针二进制 + 正确 SELinux 标签
cp /build/out/diag_probe $MNT/system/bin/diag_probe
chmod 755 $MNT/system/bin/diag_probe
python3 - <<"PYEOF"
import os
p = "/mnt/hp6/system/bin/diag_probe"
os.setxattr(p, "security.selinux", b"u:object_r:shell_exec:s0\x00")
print("xattr diag_probe:", os.getxattr(p, "security.selinux"))
p2 = "/mnt/hp6/system/bin/gsi_dump.sh"
os.setxattr(p2, "security.selinux", b"u:object_r:shell_exec:s0\x00")
print("xattr gsi_dump.sh:", os.getxattr(p2, "security.selinux"))
PYEOF

# 2b) 策略：允许 init set cold_boot_done_prop
CIL=$MNT/system/etc/selinux/plat_sepolicy.cil
grep -c "cold_boot_done_prop" $CIL || true
tail -3 $CIL
cat >> $CIL <<"EOF"

; ==== DSU port: allow init to set cold_boot_done_prop (patched) ====
(allow init cold_boot_done_prop (property_service (set)))
EOF
tail -3 $CIL

# 2c) init.rc 增加探针服务
RC=$MNT/system/etc/init/hw/init.rc
cat >> $RC <<"EOF"

# ==== DSU port: diag probe service ====
service diag_probe /system/bin/diag_probe
    class core
    user root
    oneshot
    disabled

on early-init
    start diag_probe
EOF
tail -10 $RC

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -3
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG
'

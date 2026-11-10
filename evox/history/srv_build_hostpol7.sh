P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
aarch64-linux-gnu-gcc -O2 -static -w -o /build/out/diag_probe2 /home/qinghuo/diag_probe2.c
ls -la /build/out/diag_probe2
file /build/out/diag_probe2 | head -1

SRC=/build/out/evox_socrates_system_hostpol6.img
IMG=/build/out/evox_socrates_system_hostpol7.img
MNT=/mnt/hp7
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 更新探针（短版本）
cp /build/out/diag_probe2 $MNT/system/bin/diag_probe
chmod 755 $MNT/system/bin/diag_probe
python3 - <<"PYEOF"
import os
p = "/mnt/hp7/system/bin/diag_probe"
os.setxattr(p, "security.selinux", b"u:object_r:shell_exec:s0\x00")
print("xattr:", os.getxattr(p, "security.selinux"))
PYEOF

RC=$MNT/system/etc/init/hw/init.rc
cat >> $RC <<"EOF"

# ==== DSU port: exec probe in early-init ====
on early-init
    write /metadata/gsi/dsu/stage_before_exec 1
    exec /system/bin/diag_probe
    write /metadata/gsi/dsu/stage_after_exec 1
EOF
tail -8 $RC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

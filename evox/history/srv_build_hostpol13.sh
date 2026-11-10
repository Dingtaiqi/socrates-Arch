P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol12.img
IMG=/build/out/evox_socrates_system_hostpol13.img
MNT=/mnt/hp13
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

cat >> $RC <<"EOF"

# ==== DSU port: numeric-uid exec tests ====
on early-init
    write /metadata/gsi/dsu/x_a 1
    exec - 0 0 -- /system/bin/sh -c "echo numuid > /metadata/gsi/dsu/x1"
    write /metadata/gsi/dsu/x_b 1
    exec - 0 0 -- /system/bin/toybox sh -c "echo toy > /metadata/gsi/dsu/x2"
    write /metadata/gsi/dsu/x_c 1
    exec - 0 0 -- /system/bin/diag_probe
    write /metadata/gsi/dsu/x_d 1
    exec - -- /system/bin/sh -c "echo nouid > /metadata/gsi/dsu/x3"
    write /metadata/gsi/dsu/x_e 1
EOF
tail -16 $RC

python3 - <<"PYEOF"
import os
for f in ["/system/bin/probe_dsu.sh","/system/bin/gsi_dump.sh","/system/bin/diag_probe"]:
    p="/mnt/hp13"+f
    os.setxattr(p,"security.selinux",b"u:object_r:shell_exec:s0\x00")
print("xattr ok")
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol7.img
IMG=/build/out/evox_socrates_system_hostpol8.img
MNT=/mnt/hp8
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp /home/qinghuo/probe_dsu.sh $MNT/system/bin/probe_dsu.sh
chmod 755 $MNT/system/bin/probe_dsu.sh
python3 - <<"PYEOF"
import os
p = "/mnt/hp8/system/bin/probe_dsu.sh"
os.setxattr(p, "security.selinux", b"u:object_r:shell_exec:s0\x00")
print("xattr:", os.getxattr(p, "security.selinux"))
PYEOF

RC=$MNT/system/etc/init/hw/init.rc
cat >> $RC <<"EOF"

# ==== DSU port: background shell probe via exec ====
on early-init
    write /metadata/gsi/dsu/stage_probe_start 1
    exec /system/bin/sh /system/bin/probe_dsu.sh
    write /metadata/gsi/dsu/stage_probe_launched 1
EOF
tail -8 $RC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

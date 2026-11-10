P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol10.img
IMG=/build/out/evox_socrates_system_hostpol11.img
MNT=/mnt/hp11
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

cat >> $RC <<"EOF"

# ==== DSU port: exec mechanism tests ====
on early-init
    write /metadata/gsi/dsu/t_a 1
    exec_background - root root -- /system/bin/sh -c "echo okA > /metadata/gsi/dsu/t1"
    write /metadata/gsi/dsu/t_b 1
    exec - root root -- /system/bin/sh -c "echo okB > /metadata/gsi/dsu/t2"
    write /metadata/gsi/dsu/t_c 1
    exec - root root -- /system/bin/toybox sh -c "echo okC > /metadata/gsi/dsu/t3"
    write /metadata/gsi/dsu/t_d 1
    exec - root root -- /system/bin/diag_probe
    write /metadata/gsi/dsu/t_e 1

service t_svc /system/bin/sh -c "echo okS > /metadata/gsi/dsu/t4"
    class core
    user root
    oneshot
    disabled

on early-init
    start t_svc
    write /metadata/gsi/dsu/t_f 1
EOF
tail -26 $RC

python3 - <<"PYEOF"
import os
for f in ["/system/bin/probe_dsu.sh","/system/bin/gsi_dump.sh","/system/bin/diag_probe"]:
    p="/mnt/hp11"+f
    os.setxattr(p,"security.selinux",b"u:object_r:shell_exec:s0\x00",)
print("xattr ok")
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

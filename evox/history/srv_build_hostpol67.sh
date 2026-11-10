P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol66.img
IMG=/build/out/evox_socrates_system_hostpol67.img
MNT=/mnt/hp67
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/hp67/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
strings -a $MNT/system/bin/init | grep -c "svc_stdio.log" || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

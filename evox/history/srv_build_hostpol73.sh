P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol72.img
IMG=/build/out/evox_socrates_system_hostpol73.img
MNT=/mnt/hp73
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
mkdir -p $MNT/system/bin/bootstrap
cp /build/out/misc_bins/linkerconfig $MNT/system/bin/linkerconfig
cp /build/out/misc_bins/linkerconfig $MNT/system/bin/bootstrap/linkerconfig 2>/dev/null || true
chmod 755 $MNT/system/bin/linkerconfig
python3 -c "import os; os.setxattr(\"/mnt/hp73/system/bin/linkerconfig\",\"security.selinux\",b\"u:object_r:linkerconfig_exec:s0\x00\")"
ls -la $MNT/system/bin/linkerconfig
python3 -c "import os; print(os.getxattr(\"/mnt/hp73/system/bin/linkerconfig\",\"security.selinux\"))"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

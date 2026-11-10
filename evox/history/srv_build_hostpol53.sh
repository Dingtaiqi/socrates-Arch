P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol52.img
IMG=/build/out/evox_socrates_system_hostpol53.img
MNT=/mnt/hp53
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
echo "== 原 libfs_mgr =="
ls -la $MNT/system/lib64/libfs_mgr.so
python3 -c "import os; print(os.getxattr(\"/mnt/hp53/system/lib64/libfs_mgr.so\",\"security.selinux\"))"
cp -f /build/out/libfs_mgr_trace.so $MNT/system/lib64/libfs_mgr.so
chmod 644 $MNT/system/lib64/libfs_mgr.so
python3 -c "import os; os.setxattr(\"/mnt/hp53/system/lib64/libfs_mgr.so\",\"security.selinux\",b\"u:object_r:system_lib_file:s0\x00\"); print(\"label ok\")"
ls -la $MNT/system/lib64/libfs_mgr.so
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

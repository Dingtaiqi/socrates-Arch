#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chown qinghuo /build/out/init_dsu
SRC=/build/out/evox_socrates_base27.img
IMG=/build/out/evox_socrates_base28.img
MNT=/mnt/base28
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base28/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

# 同步 libfs_mgr.so（含 data 直接 rw 挂载）
cp -f /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so $MNT/system/lib64/libfs_mgr.so
chmod 644 $MNT/system/lib64/libfs_mgr.so
python3 -c "import os; os.setxattr(\"/mnt/base28/system/lib64/libfs_mgr.so\",\"security.selinux\",b\"u:object_r:system_lib_file:s0\x00\")"

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base27.img#" gen_diff3.py > gen_diff28.py
python3 gen_diff28.py /build/out/evox_socrates_base28.img /home/qinghuo/base28.diff
chown qinghuo /home/qinghuo/base28.diff
ls -la /home/qinghuo/base28.diff
'

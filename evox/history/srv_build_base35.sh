#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base34.img
IMG=/build/out/evox_socrates_base35.img
MNT=/mnt/base35
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base35/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
strings $MNT/system/bin/init | grep -c "svc_stdio" || true
# 同时更新 libfs_mgr.so（若 out_init 有）
if [ -f /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so ]; then
  cp -f /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so $MNT/system/lib64/libfs_mgr.so
  chmod 644 $MNT/system/lib64/libfs_mgr.so
  python3 -c "import os; os.setxattr(\"/mnt/base35/system/lib64/libfs_mgr.so\",\"security.selinux\",b\"u:object_r:system_lib_file:s0\x00\")"
  echo "libfs_mgr updated"
fi
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base29.img#" gen_diff3.py > gen_diff35.py
python3 gen_diff35.py /build/out/evox_socrates_base35.img /home/qinghuo/base35.diff
chown qinghuo /home/qinghuo/base35.diff
ls -la /home/qinghuo/base35.diff
'

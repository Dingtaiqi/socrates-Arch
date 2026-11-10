#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base7.img
IMG=/build/out/evox_socrates_base8.img
MNT=/mnt/base8
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base8/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base7.img#" gen_diff3.py > gen_diff8.py
python3 gen_diff8.py /build/out/evox_socrates_base8.img /home/qinghuo/base8.diff
chown qinghuo /home/qinghuo/base8.diff
ls -la /home/qinghuo/base8.diff
'

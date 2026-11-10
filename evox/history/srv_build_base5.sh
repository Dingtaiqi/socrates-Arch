#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base4.img
IMG=/build/out/evox_socrates_base5.img
MNT=/mnt/base5
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base5/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
grep -ac "permissive before PropertyInit" $MNT/system/bin/init || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base4.img#" gen_diff3.py > gen_diff5.py
python3 gen_diff5.py /build/out/evox_socrates_base5.img /home/qinghuo/base5.diff
chown qinghuo /home/qinghuo/base5.diff
ls -la /home/qinghuo/base5.diff
'

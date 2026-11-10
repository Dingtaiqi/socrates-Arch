#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base3.img
IMG=/build/out/evox_socrates_base4.img
MNT=/mnt/base4
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base4/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
grep -ac "host precompiled" $MNT/system/bin/init || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
echo "== 生成 diff base3->base4 =="
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base3.img#" gen_diff3.py > gen_diff4.py
python3 gen_diff4.py /build/out/evox_socrates_base4.img /home/qinghuo/base4.diff
chown qinghuo /home/qinghuo/base4.diff
ls -la /home/qinghuo/base4.diff
'

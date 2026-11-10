#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base56.img
IMG=/build/out/evox_socrates_base57.img
MNT=/mnt/b57
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
python3 /home/qinghuo/patch_b57.py $MNT
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b57.py
python3 gen_diff_b57.py /build/out/evox_socrates_base57.img /home/qinghuo/base57.diff
chown qinghuo /home/qinghuo/base57.diff
ls -la /home/qinghuo/base57.diff
'

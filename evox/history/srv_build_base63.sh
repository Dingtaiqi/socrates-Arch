#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base62.img
IMG=/build/out/evox_socrates_base63.img
MNT=/mnt/b63
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
printf "\n# [dsu-user-b63] daily mode: stay in EvoX, logs slim, 600s boot watchdog\npersist.sys.dsu_daily=1\npersist.sys.dsu_return_after=0\npersist.sys.dsu_watchdog=600\n" >> $MNT/system/build.prop
tail -4 $MNT/system/build.prop
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base62.img#" gen_diff3.py > gen_diff_b63.py
python3 gen_diff_b63.py /build/out/evox_socrates_base63.img /home/qinghuo/base63.diff
chown qinghuo /home/qinghuo/base63.diff
ls -la /home/qinghuo/base63.diff
'

#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base55.img
IMG=/build/out/evox_socrates_base55b.img
MNT=/mnt/b55b
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
# 看门狗 1800 -> 600：若 10 分钟没 boot_completed 就自动重启回宿主，避免再手动长按电源
sed -i "s/^persist.sys.dsu_watchdog=1800$/persist.sys.dsu_watchdog=600/" $MNT/system/build.prop
tail -5 $MNT/system/build.prop
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b55b.py
python3 gen_diff_b55b.py /build/out/evox_socrates_base55b.img /home/qinghuo/base55b.diff
chown qinghuo /home/qinghuo/base55b.diff
ls -la /home/qinghuo/base55b.diff
'

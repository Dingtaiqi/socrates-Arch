#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base58b.img
IMG=/build/out/evox_socrates_base59.img
MNT=/mnt/b59
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cat >> $MNT/system/build.prop <<EOF

# [dsu-debug-b59] 调试：日志全开 + boot 后 60s 回宿主 + 600s 保命看门狗
persist.sys.dsu_daily=0
persist.sys.dsu_return_after=60
persist.sys.dsu_watchdog=600
EOF
tail -5 $MNT/system/build.prop
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b59.py
python3 gen_diff_b59.py /build/out/evox_socrates_base59.img /home/qinghuo/base59.diff
chown qinghuo /home/qinghuo/base59.diff
ls -la /home/qinghuo/base59.diff
'

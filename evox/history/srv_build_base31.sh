#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
I=/build/evox/out_init/target/product/socrates/system/bin/init
echo "== init 检查 =="
ls -la $I
strings $I | grep -c "svc_exit.log" || true
cp -f $I /build/out/init_dsu
chown qinghuo /build/out/init_dsu
SRC=/build/out/evox_socrates_base30.img
IMG=/build/out/evox_socrates_base31.img
MNT=/mnt/base31
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base31/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
echo "== zygote rc stdio_to_kmsg 检查 =="
grep -c "stdio_to_kmsg" $MNT/system/etc/init/hw/init.zygote64_32.rc || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base30.img#" gen_diff3.py > gen_diff31.py
python3 gen_diff31.py /build/out/evox_socrates_base31.img /home/qinghuo/base31.diff
chown qinghuo /home/qinghuo/base31.diff
ls -la /home/qinghuo/base31.diff
'

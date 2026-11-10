#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base44.img
IMG=/build/out/evox_socrates_base45.img
MNT=/mnt/b45
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 补齐 /product/fonts（fonts_customization.xml 引用的字体，177MB）=="
mkdir -p $MNT/system/evox_product/fonts
rsync -a $B/product/fonts/ $MNT/system/evox_product/fonts/
echo "fonts count: $(ls $MNT/system/evox_product/fonts | wc -l)"
du -sh $MNT/system/evox_product/fonts

echo "== 顺便补齐 xbin/usr 里可能被引用的东西 ==="
df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
ls -la $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base44.img#" gen_diff3.py > gen_diff_b45.py
python3 gen_diff_b45.py /build/out/evox_socrates_base45.img /home/qinghuo/base45.diff
chown qinghuo /home/qinghuo/base45.diff
ls -la /home/qinghuo/base45.diff
'

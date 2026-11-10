#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
FW=/build/evox/out/target/product/socrates/system/framework
SRC=/build/out/evox_socrates_base61.img
IMG=/build/out/evox_socrates_base62.img
MNT=/mnt/b62
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
echo "== 覆盖 framework 五件套（flash1+2+3）=="
cp -f $FW/services.jar $MNT/system/framework/services.jar
cp -f $FW/services.jar.prof $MNT/system/framework/services.jar.prof
cp -f $FW/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.odex
cp -f $FW/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.vdex
cp -f $FW/oat/arm64/services.art $MNT/system/framework/oat/arm64/services.art
chmod 0644 $MNT/system/framework/services.jar $MNT/system/framework/services.jar.prof $MNT/system/framework/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.art
cd $MNT/system/framework
md5sum services.jar services.jar.prof oat/arm64/services.odex oat/arm64/services.vdex oat/arm64/services.art
strings services.jar | grep -c dsu_port_flash3 || true
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b62.py
python3 gen_diff_b62.py /build/out/evox_socrates_base62.img /home/qinghuo/base62.diff
chown qinghuo /home/qinghuo/base62.diff
ls -la /home/qinghuo/base62.diff
'

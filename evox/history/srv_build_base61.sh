#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
FW=/build/evox/out/target/product/socrates/system/framework
SRC=/build/out/evox_socrates_base60.img
IMG=/build/out/evox_socrates_base61.img
MNT=/mnt/b61
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 覆盖 framework 五件套（flash1+flash2）=="
cp -f $FW/services.jar $MNT/system/framework/services.jar
cp -f $FW/services.jar.prof $MNT/system/framework/services.jar.prof
cp -f $FW/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.odex
cp -f $FW/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.vdex
cp -f $FW/oat/arm64/services.art $MNT/system/framework/oat/arm64/services.art
chmod 0644 $MNT/system/framework/services.jar $MNT/system/framework/services.jar.prof $MNT/system/framework/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.art

echo "== 校验五件套 md5（应为 504c571b / d130c2 / 7e9ef9 / 616bce / 6735f1）=="
cd $MNT/system/framework
md5sum services.jar services.jar.prof oat/arm64/services.odex oat/arm64/services.vdex oat/arm64/services.art
strings services.jar | grep -c dsu_port_flash2 || true

echo "== build.prop 尾部 =="
tail -4 $MNT/system/build.prop
df -h $MNT | tail -1
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b61.py
python3 gen_diff_b61.py /build/out/evox_socrates_base61.img /home/qinghuo/base61.diff
chown qinghuo /home/qinghuo/base61.diff
ls -la /home/qinghuo/base61.diff
'

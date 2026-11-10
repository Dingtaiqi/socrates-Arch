#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
FW=/build/evox/out/target/product/socrates/system/framework
SRC=/build/out/evox_socrates_base58b.img
IMG=/build/out/evox_socrates_base60.img
MNT=/mnt/b60
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 1) 注入 patched framework 五件套 =="
mkdir -p $MNT/system/framework/oat/arm64
cp -f $FW/services.jar $MNT/system/framework/services.jar
cp -f $FW/services.jar.prof $MNT/system/framework/services.jar.prof
cp -f $FW/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.odex
cp -f $FW/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.vdex
cp -f $FW/oat/arm64/services.art $MNT/system/framework/oat/arm64/services.art
chmod 0644 $MNT/system/framework/services.jar $MNT/system/framework/services.jar.prof $MNT/system/framework/oat/arm64/services.odex $MNT/system/framework/oat/arm64/services.vdex $MNT/system/framework/oat/arm64/services.art

echo "== 2) 校验五件套 md5 =="
cd $MNT/system/framework
md5sum services.jar services.jar.prof oat/arm64/services.odex oat/arm64/services.vdex oat/arm64/services.art

echo "== 3) build.prop 调试配置（daily=0 / 60s 回 / 600s 看门狗）=="
printf "\n# [dsu-debug-b60] debug: logs on, return 60s after boot, 600s watchdog\npersist.sys.dsu_daily=0\npersist.sys.dsu_return_after=60\npersist.sys.dsu_watchdog=600\n" >> $MNT/system/build.prop
tail -4 $MNT/system/build.prop

echo "== 4) 预检 =="
ls -la $MNT/system/bin/cameraserver
strings $MNT/system/bin/cameraserver | grep -c dsu_cam_deadlock || true
grep -c "restart cameraserver" $MNT/system/etc/init/hw/init.zygote64_32.rc || true
grep -c "class_restart cameraWatchdog" $MNT/system/etc/init/cameraserver.rc || true
df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b60.py
python3 gen_diff_b60.py /build/out/evox_socrates_base60.img /home/qinghuo/base60.diff
chown qinghuo /home/qinghuo/base60.diff
ls -la /home/qinghuo/base60.diff
'

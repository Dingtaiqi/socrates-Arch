#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base56.img
IMG=/build/out/evox_socrates_base65.img
MNT=/mnt/b65
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 只换 uicap v16（关 captive portal 误报）=="
cp -f /home/qinghuo/dsu_uicap_v16.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
bash -n $MNT/system/bin/dsu_uicap.sh && echo "uicap syntax OK"
python3 -c "import os; os.setxattr(\"/mnt/b65/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 确认相机 rc 补丁已回退（应为原版：有 restart cameraserver 行）=="
grep -c "restart cameraserver" $MNT/system/etc/init/hw/init.zygote64_32.rc || true
grep -c "class_restart cameraWatchdog" $MNT/system/etc/init/cameraserver.rc || true
echo "== build.prop daily =="
tail -5 $MNT/system/build.prop
echo "== 预检：应用/IME =="
ls $MNT/system/evox_product/app/Chrome/Chrome.apk.gz >/dev/null && echo chrome_OK
ls $MNT/system/evox_product/app/LatinIMEGooglePrebuilt/LatinIMEGooglePrebuilt.apk >/dev/null && echo gboard_OK
ls $MNT/system/evox_product/priv-app/Phonesky/Phonesky.apk >/dev/null && echo play_OK
ls -la $MNT/adb_keys | head -1
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
ls -la $IMG
echo "== gzip -1 压缩（加速下载）=="
gzip -1 -c $IMG > /build/out/evox_socrates_base65.img.gz
chown qinghuo /build/out/evox_socrates_base65.img.gz
ls -la /build/out/evox_socrates_base65.img.gz
sha256sum /build/out/evox_socrates_base65.img.gz
'

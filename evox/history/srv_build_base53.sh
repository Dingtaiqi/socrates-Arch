#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
python3 /home/qinghuo/patch_diag18.py
touch /build/evox/system/core/init/init.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -6
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "daily marker: $(strings /build/out/init_dsu | grep -c stay_in_evox || true)"

SRC=/build/out/evox_socrates_base52.img
IMG=/build/out/evox_socrates_base53.img
MNT=/mnt/b53
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/b53/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

echo "== 日用模式开关 =="
grep -q "persist.sys.dsu_daily" $MNT/system/build.prop || printf "\n# [dsu-daily] 日用模式：不自动回宿主、不写大日志（共享 persist 只有 27MB）\npersist.sys.dsu_daily=1\n" >> $MNT/system/build.prop
tail -3 $MNT/system/build.prop

echo "== 预检 =="
ls -la $MNT/adb_keys | head -1; md5sum $MNT/adb_keys
ls -la $MNT/system/lib64/libcom.android.tethering.connectivity_native.so | head -1
ls $MNT/system/evox_product/app/ModuleMetadata/ModuleMetadata.apk >/dev/null && echo ModuleMetadata_OK
echo "fonts: $(ls $MNT/system/evox_product/fonts | wc -l)"
grep -n "WIFI_SSID" $MNT/system/bin/dsu_uicap.sh | head -2

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base52.img#" gen_diff3.py > gen_diff_b53.py
python3 gen_diff_b53.py /build/out/evox_socrates_base53.img /home/qinghuo/base53.diff
chown qinghuo /home/qinghuo/base53.diff
ls -la /home/qinghuo/base53.diff
'

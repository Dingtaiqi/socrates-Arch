#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
python3 /home/qinghuo/patch_diag20.py
touch /build/evox/system/core/init/init.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -6
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "file_cfg marker: $(strings /build/out/init_dsu | grep -c dsu_daily_mode || true)"

FW=/build/evox/out/target/product/socrates/system/framework
SRC=/build/out/evox_socrates_base62.img
IMG=/build/out/evox_socrates_base64.img
MNT=/mnt/b64
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 换 init v11 =="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/b64/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

echo "== 写模式标记文件（日用停留 + 日志全开供相机排查）=="
printf "1" > $MNT/system/etc/dsu_daily_mode
printf "600" > $MNT/system/etc/dsu_watchdog
chmod 0644 $MNT/system/etc/dsu_daily_mode $MNT/system/etc/dsu_watchdog
python3 -c "import os;[os.setxattr(\"/mnt/b64/system/etc/\"+f,\"security.selinux\",b\"u:object_r:system_file:s0\x00\") for f in [\"dsu_daily_mode\",\"dsu_watchdog\"]]"
ls -la $MNT/system/etc/dsu_* 
tail -3 $MNT/system/build.prop
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base62.img#" gen_diff3.py > gen_diff_b64.py
python3 gen_diff_b64.py /build/out/evox_socrates_base64.img /home/qinghuo/base64.diff
chown qinghuo /home/qinghuo/base64.diff
ls -la /home/qinghuo/base64.diff
'

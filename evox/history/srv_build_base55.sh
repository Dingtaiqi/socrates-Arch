#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
python3 /home/qinghuo/patch_diag19.py
touch /build/evox/system/core/init/init.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -6
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "flex marker: $(strings /build/out/init_dsu | grep -c dsu_flex_wd || true)"

SRC=/build/out/evox_socrates_base54b.img
IMG=/build/out/evox_socrates_base55.img
MNT=/mnt/b55
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 换 init v10 =="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/b55/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

echo "== build.prop：切到调试模式（日志全开 + boot 后 240s 自动回宿主 + 看门狗 1800s）=="
cat >> $MNT/system/build.prop <<EOF

# [dsu-debug-b55] 调试模式覆盖（后写覆盖前面的同名属性）
persist.sys.dsu_daily=0
persist.sys.dsu_return_after=240
persist.sys.dsu_watchdog=1800
EOF
tail -6 $MNT/system/build.prop
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b55.py
python3 gen_diff_b55.py /build/out/evox_socrates_base55.img /home/qinghuo/base55.diff
chown qinghuo /home/qinghuo/base55.diff
ls -la /home/qinghuo/base55.diff
'

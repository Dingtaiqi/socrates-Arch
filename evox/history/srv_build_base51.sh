#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
python3 /home/qinghuo/patch_diag17.py
touch /build/evox/system/core/init/init.cpp /build/evox/system/core/init/property_service.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -6
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "== init 标记检查 =="
echo "adb_secure0_marker: $(strings /build/out/init_dsu | grep -c dsu_adb_secure0 || true)"
echo "uicap_script: $(strings /build/out/init_dsu | grep -c dsu_uicap.sh || true)"

SRC=/build/out/evox_socrates_base50.img
IMG=/build/out/evox_socrates_base51.img
MNT=/mnt/b51
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 替换 init =="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

echo "== 镜像根 /adb_keys（A17 system keys）=="
cp -f /home/qinghuo/adbkey.pub $MNT/adb_keys
chmod 0644 $MNT/adb_keys
chown 0:0 $MNT/adb_keys
python3 -c "import os; os.setxattr(\"$MNT/adb_keys\",\"security.selinux\",b\"u:object_r:rootfs:s0\x00\")" || true
ls -la $MNT/adb_keys
md5sum $MNT/adb_keys

echo "== uicap v10 脚本进镜像 =="
cp -f /home/qinghuo/dsu_uicap_v10.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
python3 -c "import os; os.setxattr(\"$MNT/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
ls -la $MNT/system/bin/dsu_uicap.sh

echo "== 预检：历史修复仍在 =="
ls -la $MNT/system/lib64/libcom.android.tethering.connectivity_native.so 2>/dev/null || echo MISSING_tethering_lib
ls $MNT/system/evox_product/app/ModuleMetadata/ModuleMetadata.apk 2>/dev/null || echo MISSING_ModuleMetadata
echo "fonts count: $(ls $MNT/system/evox_product/fonts 2>/dev/null | wc -l)"
ls -la $MNT/system/etc/adb_keys $MNT/system/etc/init/zzz_adb_keys.rc 2>/dev/null

df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base50.img#" gen_diff3.py > gen_diff_b51.py
python3 gen_diff_b51.py /build/out/evox_socrates_base51.img /home/qinghuo/base51.diff
chown qinghuo /home/qinghuo/base51.diff
ls -la /home/qinghuo/base51.diff
'

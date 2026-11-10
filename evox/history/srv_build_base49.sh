#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
# ---------- 1) init v8 补丁 + 重编 ----------
python3 /home/qinghuo/patch_diag15.py
touch /build/evox/system/core/init/init.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -6
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "init markers: wake=$(strings /build/out/init_dsu | grep -c "keyevent 224" || true) ldconfig=$(strings /build/out/init_dsu | grep -c ldconfig_tethering || true)"

# ---------- 2) base49 = base48 + init v8 + tethering lib + adb_keys ----------
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base48.img
IMG=/build/out/evox_socrates_base49.img
MNT=/mnt/b49
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 修 screencap: tethering 的 connectivity_native.so 拷到 /system/lib64 =="
LIB=$(find $B/apex/com.android.tethering -name "libcom.android.tethering.connectivity_native.so" -path "*lib64*" | head -1)
echo "lib=$LIB"
ls -la "$LIB"
cp -a "$LIB" $MNT/system/lib64/
chmod 0644 $MNT/system/lib64/libcom.android.tethering.connectivity_native.so
chown 0:0 $MNT/system/lib64/libcom.android.tethering.connectivity_native.so
python3 -c "import os; os.setxattr(\"$MNT/system/lib64/libcom.android.tethering.connectivity_native.so\",\"security.selinux\",b\"u:object_r:system_lib_file:s0\x00\")"

echo "== adb 公钥注入 =="
cp -f /home/qinghuo/adbkey.pub $MNT/system/etc/adb_keys
chmod 0644 $MNT/system/etc/adb_keys
python3 -c "import os; os.setxattr(\"$MNT/system/etc/adb_keys\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
cat > $MNT/system/etc/init/zzz_adb_keys.rc <<EOF
# [dsu-adb] 把本机 adb 公钥写进 /data/misc/adb/adb_keys，DSU 内 adb 免点弹窗直接授权。
# 注意 ro.adb.secure=0 在 build.prop 里无效（init builtin 先占位），只能走公钥方案。
on post-fs-data
    mkdir /data/misc/adb 0770 system shell
    copy /system/etc/adb_keys /data/misc/adb/adb_keys
    chown system shell /data/misc/adb/adb_keys
    chmod 0640 /data/misc/adb/adb_keys
EOF
chmod 0644 $MNT/system/etc/init/zzz_adb_keys.rc
python3 -c "import os; os.setxattr(\"$MNT/system/etc/init/zzz_adb_keys.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 替换 init v8 =="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base48.img#" gen_diff3.py > gen_diff_b49.py
python3 gen_diff_b49.py /build/out/evox_socrates_base49.img /home/qinghuo/base49.diff
chown qinghuo /home/qinghuo/base49.diff
ls -la /home/qinghuo/base49.diff
'

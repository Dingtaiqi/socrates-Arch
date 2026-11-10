#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
# ---------- 1) 打 init 补丁 + 重编 init ----------
python3 /home/qinghuo/patch_diag14.py
touch /build/evox/system/core/init/init.cpp
cd /build/evox
export HOME=/root CCACHE_DIR=/root/.ccache CCACHE_EXEC=/usr/bin/ccache USE_CCACHE=1 CCACHE_COMPRESS=1 LC_ALL=C OUT_DIR=out_init
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_socrates-cp2a-userdebug >/dev/null 2>&1
m init -j10 2>&1 | tail -8
cp -f out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "== init 标记 =="
echo "uicap: $(strings /build/out/init_dsu | grep -c dump_fingerprint.txt || true)"
echo "wait900: $(strings /build/out/init_dsu | grep -c reboot_after_boot || true)"

# ---------- 2) 构建 base48 = base47 + 新 init + adb 便利属性 ----------
SRC=/build/out/evox_socrates_base47.img
IMG=/build/out/evox_socrates_base48.img
MNT=/mnt/b48
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

echo "== build.prop 追加 adb 免授权 + 默认开 adb =="
cat >> $MNT/system/build.prop <<EOF

# [dsu-port] DSU 调试便利：USB adb 免授权（否则 DSU 内授权弹窗没人点，adb 一直 unauthorized）
ro.adb.secure=0
persist.sys.usb.config=mtp,adb
ro.debuggable=1
EOF
tail -6 $MNT/system/build.prop

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base47.img#" gen_diff3.py > gen_diff_b48.py
python3 gen_diff_b48.py /build/out/evox_socrates_base48.img /home/qinghuo/base48.diff
chown qinghuo /home/qinghuo/base48.diff
ls -la /home/qinghuo/base48.diff
'

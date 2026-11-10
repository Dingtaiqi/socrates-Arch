#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "== 新 init 标记 =="
echo "fsdiag_v4: $(strings /build/out/init_dsu | grep -c fsdiag_guard_fired || true)"
echo "wd1800: $(strings /build/out/init_dsu | grep -c reboot_after_boot || true)"
echo "uicap: $(strings /build/out/init_dsu | grep -c dump_activities.txt || true)"

B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base45.img
IMG=/build/out/evox_socrates_base47.img
MNT=/mnt/b47
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== P0: 补 product/app/ModuleMetadata（com.android.modulemetadata）=="
mkdir -p $MNT/system/evox_product/app
cp -a $B/product/app/ModuleMetadata $MNT/system/evox_product/app/
ls -la $MNT/system/evox_product/app/ModuleMetadata/

echo "== 替换 init（v6：看门狗1800 + boot后240s自动回宿主 + fd级fs_diag截断 + uicap截屏）=="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
ls -la $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base45.img#" gen_diff3.py > gen_diff_b47.py
python3 gen_diff_b47.py /build/out/evox_socrates_base47.img /home/qinghuo/base47.diff
chown qinghuo /home/qinghuo/base47.diff
ls -la /home/qinghuo/base47.diff
'

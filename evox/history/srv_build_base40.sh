#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chown qinghuo /build/out/init_dsu
echo "== 验证 first_api_level 补丁 =="
strings /build/out/init_dsu | grep -c "dsu-port] override" || true
SRC=/build/out/evox_socrates_base38.img
IMG=/build/out/evox_socrates_base40.img
MNT=/mnt/base40
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base40/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
ls -la $MNT/system/etc/init/zzz_dsu_mask.rc 2>/dev/null && rm -f $MNT/system/etc/init/zzz_dsu_mask.rc && echo "removed mask rc"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base38.img#" gen_diff3.py > gen_diff40.py
python3 gen_diff40.py /build/out/evox_socrates_base40.img /home/qinghuo/base40.diff
chown qinghuo /home/qinghuo/base40.diff
ls -la /home/qinghuo/base40.diff
'

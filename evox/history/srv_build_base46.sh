#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
echo "== 标记检查 =="
echo "fsdiag_v4: $(strings /build/out/init_dsu | grep -c fsdiag_guard_fired || true)"
echo "uicap: $(strings /build/out/init_dsu | grep -c dump_activities.txt || true)"
SRC=/build/out/evox_socrates_base45.img
IMG=/build/out/evox_socrates_base46.img
MNT=/mnt/b46
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base45.img#" gen_diff3.py > gen_diff_b46.py
python3 gen_diff_b46.py /build/out/evox_socrates_base46.img /home/qinghuo/base46.diff
chown qinghuo /home/qinghuo/base46.diff
ls -la /home/qinghuo/base46.diff
'

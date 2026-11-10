#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base58.img
IMG=/build/out/evox_socrates_base58b.img
MNT=/mnt/b58b
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /home/qinghuo/dsu_uicap_v16.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
bash -n $MNT/system/bin/dsu_uicap.sh && echo "uicap v16 syntax OK"
python3 -c "import os; os.setxattr(\"/mnt/b58b/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
grep -n "captive_portal_mode" $MNT/system/bin/dsu_uicap.sh | head -2
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b58b.py
python3 gen_diff_b58b.py /build/out/evox_socrates_base58b.img /home/qinghuo/base58b.diff
chown qinghuo /home/qinghuo/base58b.diff
ls -la /home/qinghuo/base58b.diff
'

#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base53.img
IMG=/build/out/evox_socrates_base53b.img
MNT=/mnt/b53b
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /home/qinghuo/dsu_uicap_v13.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
python3 -c "import os; os.setxattr(\"/mnt/b53b/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
echo "== 脚本检查 =="
ls -la $MNT/system/bin/dsu_uicap.sh
grep -c "camera_restart" $MNT/system/bin/dsu_uicap.sh || true
grep -n "pidof cameraserver" $MNT/system/bin/dsu_uicap.sh | head -2
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base52.img#" gen_diff3.py > gen_diff_b53b.py
python3 gen_diff_b53b.py /build/out/evox_socrates_base53b.img /home/qinghuo/base53b.diff
chown qinghuo /home/qinghuo/base53b.diff
ls -la /home/qinghuo/base53b.diff
'

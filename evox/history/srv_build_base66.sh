#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base65.img
IMG=/build/out/evox_socrates_base66.img
MNT=/mnt/b66
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
python3 /home/qinghuo/patch_b66_image.py
echo "== 校验 =="
ls -la $MNT/system/media/bootanimation.zip
ls $MNT/system/evox_product/app/ | head -12
tail -8 $MNT/system/bin/dsu_uicap.sh
bash -n $MNT/system/bin/dsu_uicap.sh && echo "uicap syntax OK"
cd /
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base65.img#" gen_diff3.py > gen_diff_b66.py
python3 gen_diff_b66.py /build/out/evox_socrates_base66.img /home/qinghuo/base66.diff
chown qinghuo /home/qinghuo/base66.diff
ls -la /home/qinghuo/base66.diff
'

#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base21.img
IMG=/build/out/evox_socrates_base22.img
MNT=/mnt/base22
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

CIL=$MNT/system/etc/selinux/plat_sepolicy.cil
echo "== 注入 setenforce 允许规则 =="
grep -c "setenforce" $CIL || true
cat >> $CIL <<"EOF"

;; [dsu-port] allow init/kernel to switch permissive for DSU bring-up
(allow kernel self (security (setenforce)))
(allow init self (security (setenforce)))
EOF
tail -4 $CIL
grep -c "dsu-port" $CIL || true

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base21.img#" gen_diff3.py > gen_diff22.py
python3 gen_diff22.py /build/out/evox_socrates_base22.img /home/qinghuo/base22.diff
chown qinghuo /home/qinghuo/base22.diff
ls -la /home/qinghuo/base22.diff
'

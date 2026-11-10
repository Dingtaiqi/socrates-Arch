#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chown qinghuo /build/out/init_dsu
SRC=/build/out/evox_socrates_base21.img
IMG=/build/out/evox_socrates_base23.img
MNT=/mnt/base23
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) 新 init（跳过宿主 boringssl 自检导致的 reboot）
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base23/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

# 2) 策略里允许 init/kernel 切 permissive
CIL=$MNT/system/etc/selinux/plat_sepolicy.cil
grep -c "dsu-port" $CIL >/dev/null 2>&1 || true
if ! grep -q "allow init self (security (setenforce))" $CIL; then
cat >> $CIL <<"EOF"

;; [dsu-port] allow init/kernel to switch permissive for DSU bring-up
(allow kernel self (security (setenforce)))
(allow init self (security (setenforce)))
EOF
fi
tail -3 $CIL

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base21.img#" gen_diff3.py > gen_diff23.py
python3 gen_diff23.py /build/out/evox_socrates_base23.img /home/qinghuo/base23.diff
chown qinghuo /home/qinghuo/base23.diff
ls -la /home/qinghuo/base23.diff
'

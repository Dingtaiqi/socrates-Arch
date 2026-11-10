#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base38.img
IMG=/build/out/evox_socrates_base39.img
MNT=/mnt/base39
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/zzz_dsu_mask.rc
cat > $RC <<EOF
# [dsu-mask] 屏蔽宿主 MIUI 的 product/system_ext 应用目录：
# 宿主应用（小米平台签名）与镜像 AOSP 应用（testkey）同用 android.uid.system，
# PackageManager 扫描时签名不一致会被判定为致命错误。
# 只屏蔽 app/priv-app，保留 product/etc、Media、overlay 等资源。
on early-init
    mount tmpfs tmpfs /product/app
    mount tmpfs tmpfs /product/priv-app
    mount tmpfs tmpfs /system_ext/app
    mount tmpfs tmpfs /system_ext/priv-app
EOF
chmod 644 $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
ls -la $RC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base38.img#" gen_diff3.py > gen_diff39.py
python3 gen_diff39.py /build/out/evox_socrates_base39.img /home/qinghuo/base39.diff
chown qinghuo /home/qinghuo/base39.diff
ls -la /home/qinghuo/base39.diff
'

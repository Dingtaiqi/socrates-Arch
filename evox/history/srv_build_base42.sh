#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base40.img
IMG=/build/out/evox_socrates_base42.img
MNT=/mnt/base42
umount $MNT 2>/dev/null || true
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/zzz_dsu_conflict.rc
cat > $RC <<EOF
# [dsu-conflict] 屏蔽宿主 MIUI 的包安装器：
# DSU 只替换 /system，宿主 /product/priv-app/MIUIPackageInstaller 仍在，
# 它和镜像的 GooglePackageInstaller 都响应 INSTALL_PACKAGE，
# PMS 的 "There must be exactly one installer" 会直接崩掉 system_server。
on early-init
    mount tmpfs tmpfs /product/priv-app/MIUIPackageInstaller
EOF
chmod 644 $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base40.img#" gen_diff3.py > gen_diff42.py
python3 gen_diff42.py /build/out/evox_socrates_base42.img /home/qinghuo/base42.diff
chown qinghuo /home/qinghuo/base42.diff
ls -la /home/qinghuo/base42.diff
'

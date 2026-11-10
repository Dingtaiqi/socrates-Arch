#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base40.img
IMG=/build/out/evox_socrates_base43.img
MNT=/mnt/base43
umount $MNT 2>/dev/null || true
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) 直接写进 hw/init.rc 的 post-fs-data（该文件一定被解析；post-fs-data 里 enter_default_mount_ns 之后）
INITRC=$MNT/system/etc/init/hw/init.rc
if ! grep -q "dsu-conflict-mask" $INITRC; then
  cat >> $INITRC <<EOF

# [dsu-conflict-mask] 屏蔽宿主 MIUI 包安装器（与镜像 GooglePackageInstaller 角色冲突）
on post-fs-data
    mount tmpfs tmpfs /product/priv-app/MIUIPackageInstaller
    write /metadata/gsi/dsu/mark_mask_applied 1
EOF
fi
python3 -c "import os; os.setxattr(\"$INITRC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")" || true

# 2) 独立的 rc 也保留一份 marker，用于验证 /system/etc/init 是否被扫描
RC=$MNT/system/etc/init/zzz_dsu_conflict.rc
cat > $RC <<EOF
on early-init
    write /metadata/gsi/dsu/mark_zzz_early 1
on post-fs-data
    write /metadata/gsi/dsu/mark_zzz_postfsdata 1
EOF
chmod 644 $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base40.img#" gen_diff3.py > gen_diff43.py
python3 gen_diff43.py /build/out/evox_socrates_base43.img /home/qinghuo/base43.diff
chown qinghuo /home/qinghuo/base43.diff
ls -la /home/qinghuo/base43.diff
'

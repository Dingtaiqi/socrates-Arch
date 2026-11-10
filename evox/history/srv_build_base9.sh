#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base7.img
IMG=/build/out/evox_socrates_base9.img
MNT=/mnt/base9
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 用宿主 plat_property_contexts 替换镜像的（与宿主预编译策略一致）
cp -f /build/hostctx/plat_property_contexts $MNT/system/etc/selinux/plat_property_contexts
chmod 644 $MNT/system/etc/selinux/plat_property_contexts
ls -la $MNT/system/etc/selinux/plat_property_contexts
# 也替换 system_ext 的（如果镜像有）
if [ -f $MNT/system_ext/etc/selinux/system_ext_property_contexts ]; then
  cp -f /build/hostctx/system_ext_property_contexts $MNT/system_ext/etc/selinux/system_ext_property_contexts
  echo "replaced system_ext contexts"
fi

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base7.img#" gen_diff3.py > gen_diff9.py
python3 gen_diff9.py /build/out/evox_socrates_base9.img /home/qinghuo/base9.diff
chown qinghuo /home/qinghuo/base9.diff
ls -la /home/qinghuo/base9.diff
'

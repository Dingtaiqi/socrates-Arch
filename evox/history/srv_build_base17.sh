#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
# 解包宿主 selinux 策略文件
rm -rf /build/out/host_selinux
mkdir -p /build/out/host_selinux
tar -C /build/out/host_selinux --strip-components=1 -xf /home/qinghuo/host_selinux.tar
ls /build/out/host_selinux | head -8
echo "文件数: $(find /build/out/host_selinux -type f | wc -l)"

# 基于 base16 制作 base17：替换镜像 /system/etc/selinux 为宿主策略
SRC=/build/out/evox_socrates_base16.img
IMG=/build/out/evox_socrates_base17.img
MNT=/mnt/base17
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 清空旧策略目录内容再拷贝宿主文件（保留目录本身与 mapping 子目录）
rm -rf $MNT/system/etc/selinux/*
cp -a /build/out/host_selinux/. $MNT/system/etc/selinux/
# 移除宿主目录里可能带来的冗余（system_ext_*.cil 属 system_ext 分区，留着也无害）
ls $MNT/system/etc/selinux | head -20

# 放入新 init（无 DSU 策略 hack，正常编译策略）
cp -f /build/evox/out_init/target/product/socrates/system/bin/init $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base17/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base16.img#" gen_diff3.py > gen_diff17.py
python3 gen_diff17.py /build/out/evox_socrates_base17.img /home/qinghuo/base17.diff
chown qinghuo /home/qinghuo/base17.diff
ls -la /home/qinghuo/base17.diff
'

#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base25.img
IMG=/build/out/evox_socrates_base26.img
MNT=/mnt/base26
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) 换入新 libfs_mgr.so（含 /data remount rw 补丁）
cp -f /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so $MNT/system/lib64/libfs_mgr.so
chmod 644 $MNT/system/lib64/libfs_mgr.so
python3 -c "import os; os.setxattr(\"/mnt/base26/system/lib64/libfs_mgr.so\",\"security.selinux\",b\"u:object_r:system_lib_file:s0\x00\")"
strings $MNT/system/lib64/libfs_mgr.so | grep -c "remount data rw" || true

# 2) 同步新 init（含 skip reboot_on_failure 全部）
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base26/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base25.img#" gen_diff3.py > gen_diff26.py
python3 gen_diff26.py /build/out/evox_socrates_base26.img /home/qinghuo/base26.diff
chown qinghuo /home/qinghuo/base26.diff
ls -la /home/qinghuo/base26.diff
'

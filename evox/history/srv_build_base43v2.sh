#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base42.img
IMG=/build/out/evox_socrates_base43.img
INIT=/build/out/init_dsu
MNT=/mnt/b43
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 替换 init（诊断 v2：日志轮转/有界，last_fatal.txt）=="
ls -la $INIT
cp -f $INIT $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
strings $MNT/system/bin/init | grep -c "logcat_cur.log" || true
strings $MNT/system/bin/init | grep -c "dsu_force_abilist64" || true

echo "== zygote rc: --abi-list 改成 64 位 only（镜像没有 32 位 runtime）=="
RC=$MNT/system/etc/init/hw/init.zygote64_32.rc
grep -n "abi-list" $RC || true
sed -i "s/--abi-list=arm64-v8a,armeabi-v7a,armeabi/--abi-list=arm64-v8a/g" $RC
grep -n "service zygote\|abi-list" $RC | head -5
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 新增 rc：屏蔽 /metadata/fs_diag.log（宿主 init 会把它写到 23MB 撑满 62MB /metadata）=="
cat > $MNT/system/etc/init/zzz_dsu_meta.rc <<EOF
# [dsu-meta] /metadata 只有 62MB，宿主/早期 init 会把 kmsg 全量 append 到
# /metadata/fs_diag.log（实测 23MB），导致 gsi/dsu 状态写入失败、install 报 ENOSPC。
# 用 /dev/null 覆盖它，写入直接丢弃；真正的诊断日志走 /mnt/vendor/persist/dsu（有界轮转）。
on early-init
    write /metadata/fs_diag.log ""
    mount none /dev/null /metadata/fs_diag.log bind

on post-fs-data
    write /metadata/gsi/dsu/mark_diag_v2 1
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_meta.rc
python3 -c "import os; os.setxattr(\"$MNT/system/etc/init/zzz_dsu_meta.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
ls -la $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base42.img#" gen_diff3.py > gen_diff_b43.py
python3 gen_diff_b43.py /build/out/evox_socrates_base43.img /home/qinghuo/base43.diff
chown qinghuo /home/qinghuo/base43.diff
ls -la /home/qinghuo/base43.diff
'

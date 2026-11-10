#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base41.img
IMG=/build/out/evox_socrates_base41b.img
MNT=/mnt/b41b
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/zzz_dsu_parts.rc
cat > $RC <<EOF
# [dsu-parts] 用镜像内置的 EvoX system_ext / product 覆盖 DSU 里来自宿主的 MIUI 分区。
# 原因：DSU 只替换 /system，宿主 /product、/system_ext 是 MIUI 应用（小米平台签名），
# 与镜像 AOSP 应用（testkey）签名不一致却同用 android.uid.system，PackageManager 会崩；
# 且镜像 /system 本身不含 SystemUI/Settings/Launcher/LineageSettingsProvider
# （这些在 EvoX 的 system_ext / product 里）。
# 时机用 post-fs-data：base43 实测宿主 fstab 会在 fs 阶段用 overlayfs 再挂
# /product/priv-app 等目录，早于它的 mount 会被覆盖；post-fs-data 晚于所有 mount_all。
on post-fs-data
    mount none /system/evox_system_ext /system_ext bind
    mount none /system/evox_product /product bind
    write /metadata/gsi/dsu/mark_parts_mounted 1
EOF
chmod 644 $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 确认关键 APK 都在 =="
ls -la $MNT/system/evox_system_ext/priv-app/LineageSettingsProvider/ 2>/dev/null || echo "LineageSettingsProvider MISSING in system_ext"
ls -d $MNT/system/evox_system_ext/priv-app/SystemUIGoogle $MNT/system/evox_system_ext/priv-app/SettingsGoogle 2>/dev/null
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base41.img#" gen_diff3.py > gen_diff_b41b.py
python3 gen_diff_b41b.py /build/out/evox_socrates_base41b.img /home/qinghuo/base41b.diff
chown qinghuo /home/qinghuo/base41b.diff
ls -la /home/qinghuo/base41b.diff
'

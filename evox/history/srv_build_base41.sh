#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base40.img
IMG=/build/out/evox_socrates_base41.img
MNT=/mnt/base41
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
truncate -s 2791728742 $IMG
e2fsck -f -y $IMG > /tmp/fsck1.log 2>&1 || true
resize2fs $IMG > /tmp/rsz.log 2>&1
tail -1 /tmp/rsz.log
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 复制 system_ext（去 oat，去掉 3 个超大非必要 app）=="
mkdir -p $MNT/system/evox_system_ext
rsync -a --exclude "oat/" \
  --exclude "app/UdfpsAnimations/" --exclude "app/OmniJaws/" \
  --exclude "priv-app/MagicPortraitWallpapers/" \
  $B/system_ext/ $MNT/system/evox_system_ext/
du -sh $MNT/system/evox_system_ext

echo "== 复制 product 子集 =="
mkdir -p $MNT/system/evox_product
rsync -a --exclude "oat/" \
  $B/product/etc $B/product/overlay $B/product/framework $B/product/lib64 \
  $B/product/app/WebViewGoogle $B/product/app/TrichromeLibrary \
  $MNT/system/evox_product/
[ -d $B/product/apex ] && rsync -a $B/product/apex $MNT/system/evox_product/ || true
du -sh $MNT/system/evox_product

echo "== 写 bind mount rc =="
RC=$MNT/system/etc/init/zzz_dsu_parts.rc
cat > $RC <<EOF
# [dsu-parts] 用镜像内置的 EvoX system_ext / product 覆盖 DSU 中来自宿主的 MIUI 分区。
# 原因：DSU 只替换 /system，宿主 /product、/system_ext 里是 MIUI 应用（小米平台签名），
# 与镜像 AOSP 应用（testkey）签名不一致却同用 android.uid.system，PackageManager 直接崩；
# 且镜像本身不含 SystemUI/Settings/Launcher（它们在 EvoX 的 system_ext 里）。
on post-fs
    mount none /system/evox_system_ext /system_ext bind
    mount none /system/evox_product /product bind
EOF
chmod 644 $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 空间检查 =="
df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG

echo "== 生成差分 =="
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base40.img#" gen_diff3.py > gen_diff41.py
python3 gen_diff41.py /build/out/evox_socrates_base41.img /home/qinghuo/base41.diff
chown qinghuo /home/qinghuo/base41.diff
ls -la /home/qinghuo/base41.diff
'

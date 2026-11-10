#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base41b.img
IMG=/build/out/evox_socrates_base42.img
MNT=/mnt/b42
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
EP=$MNT/system/evox_product

echo "== 清掉放错层级的 WebView/Trichrome 目录 =="
rm -rf $EP/WebViewGoogle $EP/TrichromeLibrary

echo "== 按 AOSP 压缩 APK 布局放入：Module(含 .apk.gz) + Module-Stub(含 stub.apk) =="
mkdir -p $EP/app/WebViewGoogle $EP/app/WebViewGoogle-Stub
mkdir -p $EP/app/TrichromeLibrary $EP/app/TrichromeLibrary-Stub
cp -a $B/product/app/WebViewGoogle/WebViewGoogle.apk.gz              $EP/app/WebViewGoogle/
cp -a $B/product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk      $EP/app/WebViewGoogle-Stub/
cp -a $B/product/app/TrichromeLibrary/TrichromeLibrary.apk.gz        $EP/app/TrichromeLibrary/
cp -a $B/product/app/TrichromeLibrary-Stub/TrichromeLibrary-Stub.apk $EP/app/TrichromeLibrary-Stub/
ls -laR $EP/app | head -20

echo "== 检查所有 -Stub 目录是否还有遗漏 =="
find $B/product $B/system_ext -maxdepth 3 -type d -name "*-Stub" 2>/dev/null

echo "== 空间 =="
df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base41b.img#" gen_diff3.py > gen_diff_b42.py
python3 gen_diff_b42.py /build/out/evox_socrates_base42.img /home/qinghuo/base42.diff
chown qinghuo /home/qinghuo/base42.diff
ls -la /home/qinghuo/base42.diff

echo "== PMS stub 解压调用点 =="
cd /build/evox
grep -rn "decompressFiles(" frameworks/base/services/core/java/com/android/server/pm/*.java | head -5
'

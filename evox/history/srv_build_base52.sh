#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base51.img
IMG=/build/out/evox_socrates_base52.img
MNT=/mnt/b52
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 替换 uicap 脚本为 v12（SSID=REDACTED_WIFI_SSID，camera AIDL 诊断）=="
cp -f /home/qinghuo/dsu_uicap_v12.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
python3 -c "import os; os.setxattr(\"/mnt/b52/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
ls -la $MNT/system/bin/dsu_uicap.sh
grep -n "WIFI_SSID\|WIFI_SCAN_FILTER" $MNT/system/bin/dsu_uicap.sh | head -3

echo "== 预检：历史修复 =="
ls -la $MNT/adb_keys 2>/dev/null | head -1
md5sum $MNT/adb_keys
ls -la $MNT/system/lib64/libcom.android.tethering.connectivity_native.so 2>/dev/null | head -1
ls $MNT/system/evox_product/app/ModuleMetadata/ModuleMetadata.apk >/dev/null && echo ModuleMetadata_OK
echo "fonts: $(ls $MNT/system/evox_product/fonts | wc -l)"

df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base51.img#" gen_diff3.py > gen_diff_b52.py
python3 gen_diff_b52.py /build/out/evox_socrates_base52.img /home/qinghuo/base52.diff
chown qinghuo /home/qinghuo/base52.diff
ls -la /home/qinghuo/base52.diff
'

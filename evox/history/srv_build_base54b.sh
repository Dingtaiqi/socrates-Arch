#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
B=/build/evox/out/target/product/socrates
# 关键：从 base53b（= 本地 base53 的同一份，sha 3b70d654）出发，保证 diff 基线一致
SRC=/build/out/evox_socrates_base53b.img
IMG=/build/out/evox_socrates_base54b.img
MNT=/mnt/b54b
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
EP=$MNT/system/evox_product

echo "== 1) 默认应用（含 Chrome-Stub！）=="
mkdir -p $EP/app $EP/priv-app
cp -a $B/product/app/Chrome $EP/app/
cp -a $B/product/app/Chrome-Stub $EP/app/
cp -a $B/product/app/Aperture $EP/app/
cp -a $B/product/app/LatinIMEGooglePrebuilt $EP/app/
cp -a $B/product/app/GoogleContacts $EP/app/
cp -a $B/product/priv-app/GoogleDialer $EP/priv-app/
cp -a $B/product/priv-app/Phonesky $EP/priv-app/
echo "app: $(du -sk $EP/app | cut -f1)KB priv-app: $(du -sk $EP/priv-app | cut -f1)KB"

echo "== 2) 相机 rc 补丁（zygote 去 restart cameraserver + cameraserver.rc 去 class_restart）=="
for f in $MNT/system/etc/init/hw/init.zygote32.rc $MNT/system/etc/init/hw/init.zygote64.rc $MNT/system/etc/init/hw/init.zygote64_32.rc; do
  [ -f "$f" ] || continue
  cp -a "$f" "$f.orig" 2>/dev/null || true
  sed -i "/onrestart restart cameraserver/d" "$f"
  echo "$f left=$(grep -c "restart cameraserver" "$f" || true)"
done
CS=$MNT/system/etc/init/cameraserver.rc
cp -a $CS $CS.orig 2>/dev/null || true
sed -i "/onrestart class_restart cameraWatchdog/d" $CS

echo "== 3) Aperture default-permissions =="
mkdir -p $MNT/system/etc/default-permissions
cat > $MNT/system/etc/default-permissions/dsu-aperture.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<exceptions>
    <exception package="org.lineageos.aperture">
        <permission name="android.permission.CAMERA" fixed="false"/>
        <permission name="android.permission.RECORD_AUDIO" fixed="false"/>
        <permission name="android.permission.ACCESS_MEDIA_LOCATION" fixed="false"/>
        <permission name="android.permission.READ_MEDIA_IMAGES" fixed="false"/>
        <permission name="android.permission.READ_MEDIA_VIDEO" fixed="false"/>
    </exception>
</exceptions>
EOF
chmod 0644 $MNT/system/etc/default-permissions/dsu-aperture.xml

echo "== 4) uicap v15 =="
cp -f /home/qinghuo/dsu_uicap_v15.sh $MNT/system/bin/dsu_uicap.sh
chmod 0755 $MNT/system/bin/dsu_uicap.sh
bash -n $MNT/system/bin/dsu_uicap.sh && echo "uicap syntax OK"
python3 -c "import os; os.setxattr(\"/mnt/b54b/system/bin/dsu_uicap.sh\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
python3 -c "import os; os.setxattr(\"/mnt/b54b/system/etc/default-permissions/dsu-aperture.xml\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

echo "== 5) 预检 =="
ls $EP/app/Chrome/Chrome.apk.gz $EP/app/Chrome-Stub/Chrome-Stub.apk $EP/app/Aperture/Aperture.apk >/dev/null && echo chrome+aperture_OK
ls $EP/priv-app/Phonesky/Phonesky.apk $EP/priv-app/GoogleDialer/GoogleDialer.apk $EP/app/LatinIMEGooglePrebuilt/LatinIMEGooglePrebuilt.apk >/dev/null && echo gboard+dialer+play_OK
ls $EP/app/GoogleContacts/ 2>/dev/null | head -2
df -h $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base53b.img#" gen_diff3.py > gen_diff_b54b.py
python3 gen_diff_b54b.py /build/out/evox_socrates_base54b.img /home/qinghuo/base54b.diff
chown qinghuo /home/qinghuo/base54b.diff
ls -la /home/qinghuo/base54b.diff
'

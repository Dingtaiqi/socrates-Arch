#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base56.img
IMG=/build/out/evox_socrates_base58.img
MNT=/mnt/b58
NEWCAM=/build/evox/out/target/product/socrates/system/bin/cameraserver
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 1) 重新打相机 rc 补丁（zygote 去 restart cameraserver + cameraserver.rc 去 class_restart）=="
for f in $MNT/system/etc/init/hw/init.zygote32.rc $MNT/system/etc/init/hw/init.zygote64.rc $MNT/system/etc/init/hw/init.zygote64_32.rc; do
  [ -f "$f" ] || continue
  sed -i "/onrestart restart cameraserver/d" "$f"
  echo "$f left=$(grep -c "restart cameraserver" "$f" || true)"
done
sed -i "/onrestart class_restart cameraWatchdog/d" $MNT/system/etc/init/cameraserver.rc

echo "== 2) 替换 cameraserver 为 UidPolicy 死锁修复版 =="
ls -la $NEWCAM
strings $NEWCAM | grep -c dsu_cam_deadlock
cp -f $NEWCAM $MNT/system/bin/cameraserver
chmod 0755 $MNT/system/bin/cameraserver
python3 -c "import os; os.setxattr(\"/mnt/b58/system/bin/cameraserver\",\"security.selinux\",b\"u:object_r:cameraserver_exec:s0\x00\")" || true

echo "== 3) 预检 =="
ls -la $MNT/system/bin/cameraserver
grep -c "restart cameraserver" $MNT/system/etc/init/hw/init.zygote64_32.rc || true
grep -c "class_restart" $MNT/system/etc/init/cameraserver.rc || true
tail -5 $MNT/system/build.prop
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b58.py
python3 gen_diff_b58.py /build/out/evox_socrates_base58.img /home/qinghuo/base58.diff
chown qinghuo /home/qinghuo/base58.diff
ls -la /home/qinghuo/base58.diff
'

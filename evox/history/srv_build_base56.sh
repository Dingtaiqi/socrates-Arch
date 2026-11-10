#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base55.img
IMG=/build/out/evox_socrates_base56.img
MNT=/mnt/b56
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 回退相机 rc 补丁（恢复 b53 行为，先保证能 boot）=="
for f in $MNT/system/etc/init/hw/init.zygote32.rc $MNT/system/etc/init/hw/init.zygote64.rc $MNT/system/etc/init/hw/init.zygote64_32.rc $MNT/system/etc/init/cameraserver.rc; do
  if [ -f "$f.orig" ]; then cp -f "$f.orig" "$f"; echo "restored $f"; else echo "NO ORIG: $f"; fi
done
echo "zygote 里 restart cameraserver 行数: $(grep -c "restart cameraserver" $MNT/system/etc/init/hw/init.zygote64_32.rc || true)"
echo "cameraserver.rc class_restart 行数: $(grep -c "class_restart" $MNT/system/etc/init/cameraserver.rc || true)"

echo "== build.prop：日用模式 + 600s 保命看门狗 =="
cat >> $MNT/system/build.prop <<EOF

# [dsu-user-b56] 日用：boot 后停留 EvoX；只在从未 boot_completed 时 600s 自动回宿主保命
persist.sys.dsu_daily=1
persist.sys.dsu_return_after=0
persist.sys.dsu_watchdog=600
EOF
tail -5 $MNT/system/build.prop
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b56.py
python3 gen_diff_b56.py /build/out/evox_socrates_base56.img /home/qinghuo/base56.diff
chown qinghuo /home/qinghuo/base56.diff
ls -la /home/qinghuo/base56.diff
'

#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chmod 755 /build/out/init_dsu
SRC=/build/out/evox_socrates_base43.img
IMG=/build/out/evox_socrates_base44.img
MNT=/mnt/b44
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== 替换 init（含 fs_diag 定期截断保护）=="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"$MNT/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
echo "fsdiag_guard string: $(strings $MNT/system/bin/init | grep -c fsdiag_guard_fired || true)"

echo "== 删除把 audioserver/cameraserver/media/mediadrm 替换成 /system/bin/true 的历史 stub rc =="
for f in zzz_dsu_override5.rc zzz_dsu_override6.rc; do
  if [ -f $MNT/system/etc/init/$f ]; then rm -f $MNT/system/etc/init/$f; echo "removed $f"; fi
done
echo "== 确认没有残留 stub（应只剩 MIUI 无关服务的 true stub）=="
grep -rn "/system/bin/true" $MNT/system/etc/init/ | head -10 || true

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
ls -la $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base43.img#" gen_diff3.py > gen_diff_b44.py
python3 gen_diff_b44.py /build/out/evox_socrates_base44.img /home/qinghuo/base44.diff
chown qinghuo /home/qinghuo/base44.diff
ls -la /home/qinghuo/base44.diff
'

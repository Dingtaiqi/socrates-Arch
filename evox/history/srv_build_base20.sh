#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
cp -f /build/evox/out_init/target/product/socrates/system/bin/init /build/out/init_dsu
chown qinghuo /build/out/init_dsu
SRC=/build/out/evox_socrates_base19.img
IMG=/build/out/evox_socrates_base20.img
MNT=/mnt/base20
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/base20/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

# rc 阶段标记（写到 /metadata，确认 init 卡在哪个 trigger）
cat > $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"
# [dsu-port] 阶段标记 + adb 强制
on early-init
    write /metadata/gsi/dsu/rc_early_init 1

on init
    write /metadata/gsi/dsu/rc_init 1

on late-init
    write /metadata/gsi/dsu/rc_late_init 1

on boot
    write /metadata/gsi/dsu/rc_boot 1
    setprop sys.usb.config mtp,adb
    start adbd

on property:sys.boot_completed=1
    write /metadata/gsi/dsu/stage_boot_completed 1

on property:init.svc.adbd=running
    write /metadata/gsi/dsu/stage_adbd_running 1

on property:init.svc.zygote=running
    write /metadata/gsi/dsu/stage_zygote_running 1
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override4.rc
python3 -c "import os; os.setxattr(\"/mnt/base20/system/etc/init/zzz_dsu_override4.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
ls -la $MNT/system/etc/init/zzz_dsu_override4.rc

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base19.img#" gen_diff3.py > gen_diff20.py
python3 gen_diff20.py /build/out/evox_socrates_base20.img /home/qinghuo/base20.diff
chown qinghuo /home/qinghuo/base20.diff
ls -la /home/qinghuo/base20.diff
'

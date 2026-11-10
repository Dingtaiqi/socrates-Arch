P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol36.img
IMG=/build/out/evox_socrates_system_hostpol37.img
MNT=/mnt/hp37
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"
# [dsu-port] 启动诊断 & adb 强制
on boot
    setprop sys.usb.config mtp,adb
    start adbd

on property:sys.boot_completed=1
    write /metadata/gsi/dsu/stage_boot_completed 1

on property:init.svc.adbd=running
    write /metadata/gsi/dsu/stage_adbd_running 1

on property:init.svc.zygote=running
    write /metadata/gsi/dsu/stage_zygote_running 1

on property:init.svc.media=running
    write /metadata/gsi/dsu/stage_media_running 1
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override4.rc
python3 -c "import os; os.setxattr(\"/mnt/hp37/system/etc/init/zzz_dsu_override4.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
cat $MNT/system/etc/init/zzz_dsu_override4.rc
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

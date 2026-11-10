P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol4.img
IMG=/build/out/evox_socrates_system_hostpol5.img
MNT=/mnt/hp5
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

cat >> $RC <<"EOF"

# ==== DSU port: coldboot workaround + ueventd markers ====
on early-init
    setprop ro.cold_boot_done true

on property:ro.cold_boot_done=true
    write /metadata/gsi/dsu/stage_coldboot_prop 1

on property:init.svc.ueventd=running
    write /metadata/gsi/dsu/stage_ueventd_running 1

on property:init.svc.ueventd=stopped
    write /metadata/gsi/dsu/stage_ueventd_stopped 1

on property:init.svc.ueventd=restarting
    write /metadata/gsi/dsu/stage_ueventd_restarting 1
EOF
echo "=== 追加完成 ==="
tail -22 $RC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -3
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG
'

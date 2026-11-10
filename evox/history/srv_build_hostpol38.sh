P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol37.img
IMG=/build/out/evox_socrates_system_hostpol38.img
MNT=/mnt/hp38
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_probe2.rc <<"EOF"
# [dsu-port] zygote / apexd / crypto 状态探针
on property:init.svc.zygote=restarting
    write /metadata/gsi/dsu/p_zygote_restarting 1
on property:init.svc.zygote=stopped
    write /metadata/gsi/dsu/p_zygote_stopped 1
on property:init.svc.zygote=running
    write /metadata/gsi/dsu/p_zygote_running 1
on property:apexd.status=ready
    write /metadata/gsi/dsu/p_apexd_ready 1
on property:apexd.status=failed
    write /metadata/gsi/dsu/p_apexd_failed 1
on property:apexd.status=starting
    write /metadata/gsi/dsu/p_apexd_starting 1
on property:ro.crypto.state=encrypted
    write /metadata/gsi/dsu/p_crypto_encrypted 1
on property:ro.crypto.state=unencrypted
    write /metadata/gsi/dsu/p_crypto_unencrypted 1
on property:sys.boot_completed=1
    write /metadata/gsi/dsu/p_boot_completed 1
on boot
    write /metadata/gsi/dsu/p_boot_trigger ${apexd.status}
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_probe2.rc
python3 -c "import os; os.setxattr(\"/mnt/hp38/system/etc/init/zzz_dsu_probe2.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

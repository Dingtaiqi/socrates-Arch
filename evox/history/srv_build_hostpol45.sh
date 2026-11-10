P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol44.img
IMG=/build/out/evox_socrates_system_hostpol45.img
MNT=/mnt/hp45
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 原 zygote64.rc 内容 ====="
cat $MNT/system/etc/init/hw/init.zygote64.rc

cat > $MNT/system/etc/init/zzz_dsu_zygote_dbg.rc <<"EOF"
# [dsu-port] 覆盖 zygote 服务定义，增加 stdio_to_kmsg 以便看到崩溃原因
service zygote /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
    class main
    priority -20
    user root
    group root readproc reserved_disk
    socket zygote stream 660 root system
    socket usap_pool_primary stream 660 root system
    onrestart exec_background - system system -- /system/bin/vdc volume abort_fuse
    task_profiles ProcessCapacityHigh MaxPerformance
    stdio_to_kmsg
    override
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_zygote_dbg.rc
python3 -c "import os; os.setxattr(\"/mnt/hp45/system/etc/init/zzz_dsu_zygote_dbg.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

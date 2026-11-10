P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol44.img
IMG=/build/out/evox_socrates_system_hostpol46.img
MNT=/mnt/hp46
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_zygote_dbg.rc <<"EOF"
# [dsu-port] zygote 服务完整覆盖（保留原选项）+ stdio_to_kmsg 捕获崩溃原因
service zygote /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
    class main
    priority -20
    user root
    group root readproc reserved_disk
    rlimit nofile 32768 262144
    socket zygote stream 660 root system
    socket usap_pool_primary stream 660 root system
    onrestart exec_background - system system -- /system/bin/vdc volume abort_fuse
    onrestart write /sys/power/state on
    onrestart write /sys/power/wake_lock zygote_kwl
    onrestart restart audioserver
    onrestart restart cameraserver
    onrestart restart media
    onrestart restart --only-if-running media.tuner
    onrestart restart netd
    onrestart restart wificond
    task_profiles ProcessCapacityHigh MaxPerformance
    critical window=${zygote.critical_window.minute:-off} target=zygote-fatal
    stdio_to_kmsg
    override
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_zygote_dbg.rc
python3 -c "import os; os.setxattr(\"/mnt/hp46/system/etc/init/zzz_dsu_zygote_dbg.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol39.img
IMG=/build/out/evox_socrates_system_hostpol40.img
MNT=/mnt/hp40
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_override6.rc <<"EOF"
# [dsu-port] 批量屏蔽在 DSU 下崩溃循环的服务（依赖 vendor HAL，DSU 下不稳定）
service media /system/bin/true
    class main
    user root
    group root
    disabled
    override

service mediadrm /system/bin/true
    class main
    user root
    group root
    disabled
    override

service cameraserver /system/bin/true
    class main
    user root
    group root
    disabled
    override

service audioserver /system/bin/true
    class main
    user root
    group root
    disabled
    override
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override6.rc
python3 -c "import os; os.setxattr(\"/mnt/hp40/system/etc/init/zzz_dsu_override6.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

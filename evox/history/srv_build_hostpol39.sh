P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol38.img
IMG=/build/out/evox_socrates_system_hostpol39.img
MNT=/mnt/hp39
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_override5.rc <<"EOF"
# [dsu-port] 屏蔽 DSU 下崩溃循环的媒体服务（mediaserver 缺 codec 会 crash-loop 拖死 init）
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
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override5.rc
python3 -c "import os; os.setxattr(\"/mnt/hp39/system/etc/init/zzz_dsu_override5.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

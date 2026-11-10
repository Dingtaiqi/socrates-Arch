P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol67.img
IMG=/build/out/evox_socrates_system_hostpol68.img
MNT=/mnt/hp68
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cat >> $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"

# [dsu-port] app_process 自检：--help 应输出用法；zygote 模式复现崩溃
on zygote-start
    exec - root root -- /system/bin/app_process64 --help
    exec - root root -- /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg2
EOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

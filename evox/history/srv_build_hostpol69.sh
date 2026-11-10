P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol68.img
IMG=/build/out/evox_socrates_system_hostpol69.img
MNT=/mnt/hp69
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cat >> $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"

# [dsu-port] 验证 stderr 捕获链路：date 应输出到 svc_stdio.log
on zygote-start
    exec - root root -- /system/bin/date
    exec - root root -- /system/bin/app_process64
EOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol60.img
IMG=/build/out/evox_socrates_system_hostpol61.img
MNT=/mnt/hp61
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cat > $MNT/system/etc/init/zzz_dsu_zygote_runner.rc <<"EOF"
# [dsu-port] 用 init 域 runner 捕获 app_process stderr（显式 seclabel）
service zygote_runner /system/bin/zygote_runner
    class late_start
    user root
    group root
    seclabel u:r:init:s0
    disabled
    oneshot

on zygote-start
    start zygote_runner
EOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

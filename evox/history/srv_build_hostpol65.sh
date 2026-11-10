P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol64.img
IMG=/build/out/evox_socrates_system_hostpol65.img
MNT=/mnt/hp65
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
python3 -c "import os; os.setxattr(\"/mnt/hp65/system/bin/zygote_runner\",\"security.selinux\",b\"u:object_r:gsid_exec:s0\x00\")"
cat > $MNT/system/etc/init/zzz_dsu_zygote_runner.rc <<"EOF"
# [dsu-port] gsid 域 runner：记录环境 + 尝试 exec app_process
service zygote_runner /system/bin/zygote_runner
    class late_start
    user root
    group root
    seclabel u:r:gsid:s0
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

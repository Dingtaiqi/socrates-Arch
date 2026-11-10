P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
aarch64-linux-gnu-gcc -O2 -static -o /tmp/zygote_runner2 /home/qinghuo/zygote_runner2.c
ls -la /tmp/zygote_runner2

SRC=/build/out/evox_socrates_system_hostpol63.img
IMG=/build/out/evox_socrates_system_hostpol64.img
MNT=/mnt/hp64
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp /tmp/zygote_runner2 $MNT/system/bin/zygote_runner
chmod 755 $MNT/system/bin/zygote_runner
python3 -c "import os; os.setxattr(\"/mnt/hp64/system/bin/zygote_runner\",\"security.selinux\",b\"u:object_r:vold_exec:s0\x00\")"

cat > $MNT/system/etc/init/zzz_dsu_zygote_runner.rc <<"EOF"
# [dsu-port] vold 域 runner：捕获 app_process stderr 到 /metadata
service zygote_runner /system/bin/zygote_runner
    class late_start
    user root
    group root
    seclabel u:r:vold:s0
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

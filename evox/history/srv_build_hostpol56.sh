P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol49.img
IMG=/build/out/evox_socrates_system_hostpol56.img
MNT=/mnt/hp56
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/hp56/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

# 追加 app_process 诊断 exec 到 override4.rc
cat >> $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"

# [dsu-port] 用 init 域直接跑 app_process 捕获真实错误（stderr -> /metadata）
on zygote-start
    exec - root root -- /system/bin/sh -c "/system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg >/dev/null 2>/metadata/gsi/dsu/appproc_dbg.log; echo exit=$? >>/metadata/gsi/dsu/appproc_dbg.log"
EOF
tail -6 $MNT/system/etc/init/zzz_dsu_override4.rc
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

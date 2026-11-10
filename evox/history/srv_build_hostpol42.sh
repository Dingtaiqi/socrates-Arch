P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol41.img
IMG=/build/out/evox_socrates_system_hostpol42.img
MNT=/mnt/hp42
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== kmsg_dump 标签改为 init_exec =="
python3 -c "import os; os.setxattr(\"/mnt/hp42/system/bin/kmsg_dump\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\"); print(os.getxattr(\"/mnt/hp42/system/bin/kmsg_dump\",\"security.selinux\"))"

echo "== rc: 用 exec_background + 诊断 =="
cat > $MNT/system/etc/init/zzz_dsu_kmsgdump.rc <<"EOF"
# [dsu-port] kmsg 转储（init 域执行）
on post-fs-data
    exec_background - root root -- /system/bin/kmsg_dump
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_kmsgdump.rc
python3 -c "import os; os.setxattr(\"/mnt/hp42/system/etc/init/zzz_dsu_kmsgdump.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "== 编译 kmsg_dump =="
aarch64-linux-gnu-gcc -O2 -static -o /tmp/kmsg_dump /home/qinghuo/kmsg_dump.c
ls -la /tmp/kmsg_dump

echo "== 新建 hostpol41（kmsg_dump + rc exec）=="
SRC=/build/out/evox_socrates_system_hostpol40.img
IMG=/build/out/evox_socrates_system_hostpol41.img
MNT=/mnt/hp41
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp /tmp/kmsg_dump $MNT/system/bin/kmsg_dump
chmod 755 $MNT/system/bin/kmsg_dump
python3 -c "import os; os.setxattr(\"/mnt/hp41/system/bin/kmsg_dump\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"

cat > $MNT/system/etc/init/zzz_dsu_kmsgdump.rc <<"EOF"
# [dsu-port] 用 exec_background 在 init 域里跑 kmsg 转储二进制
on post-fs-data
    exec_background - root root -- /system/bin/kmsg_dump
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_kmsgdump.rc
python3 -c "import os; os.setxattr(\"/mnt/hp41/system/etc/init/zzz_dsu_kmsgdump.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

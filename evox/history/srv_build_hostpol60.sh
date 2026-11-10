P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "== 编译 zygote_runner =="
aarch64-linux-gnu-gcc -O2 -static -o /tmp/zygote_runner /home/qinghuo/zygote_runner.c
ls -la /tmp/zygote_runner

SRC=/build/out/evox_socrates_system_hostpol59.img
IMG=/build/out/evox_socrates_system_hostpol60.img
MNT=/mnt/hp60
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp /tmp/zygote_runner $MNT/system/bin/zygote_runner
chmod 755 $MNT/system/bin/zygote_runner
python3 -c "import os; os.setxattr(\"/mnt/hp60/system/bin/zygote_runner\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

cat > $MNT/system/etc/init/zzz_dsu_zygote_runner.rc <<"EOF"
# [dsu-port] 用 init 域 runner 捕获 app_process stderr
on zygote-start
    exec - root root -- /system/bin/zygote_runner
EOF

# 删掉之前无效的 zygote_dbg service 定义（避免 socket/服务冲突）
rm -f $MNT/system/etc/init/zzz_dsu_appproc_dbg.rc

df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

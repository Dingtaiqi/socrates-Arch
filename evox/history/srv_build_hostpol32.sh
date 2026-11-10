P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "===== 1. 编译 kmsg 测试工具 ====="
cd /tmp
aarch64-linux-gnu-gcc -O2 -static -o /tmp/kmsgtest /home/qinghuo/kmsgtest.c
ls -la /tmp/kmsgtest
chown qinghuo /tmp/kmsgtest

echo "===== 2. 构建 hostpol32（用 hostpol28 的 90s init）====="
SRC=/build/out/evox_socrates_system_hostpol31.img
INITS=/build/out/evox_socrates_system_hostpol28.img
IMG=/build/out/evox_socrates_system_hostpol32.img
MNT=/mnt/hp32
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
# 从 hostpol28 提取 90s watchdog 的 init
umount /mnt/hp28b 2>/dev/null || true
mkdir -p /mnt/hp28b
mount -o loop,ro $INITS /mnt/hp28b
cp -f /mnt/hp28b/system/bin/init /tmp/init_90s
umount /mnt/hp28b
cp -f /tmp/init_90s $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "
import os
p=\"/mnt/hp32/system/bin/init\"
os.setxattr(p,\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")
print(\"init 90s ok, kmsg dump str:\", b\"kmsg.log\" in open(p,\"rb\").read())
"
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG /tmp/kmsgtest
sha256sum $IMG
'

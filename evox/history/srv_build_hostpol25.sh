P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol22.img
IMG=/build/out/evox_socrates_system_hostpol25.img
MNT=/mnt/hp25
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 替换 init（含 kmsg dump）====="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init

echo "===== 替换 apexd（去 O_SYNC）====="
cp -f /build/out/apexd_dsu $MNT/system/bin/apexd
chmod 755 $MNT/system/bin/apexd

python3 - <<"PYEOF"
import os
pi = "/mnt/hp25/system/bin/init"
os.setxattr(pi, "security.selinux", b"u:object_r:init_exec:s0\x00")
pa = "/mnt/hp25/system/bin/apexd"
os.setxattr(pa, "security.selinux", b"u:object_r:apexd_exec:s0\x00")
di = open(pi, "rb").read()
da = open(pa, "rb").read()
print("init has kmsg dump:", b"dsu_kmsg_dump" in di)
print("apexd has dsu-port:", b"dsu-port" in da)
print("init label:", os.getxattr(pi,"security.selinux"))
print("apexd label:", os.getxattr(pa,"security.selinux"))
PYEOF
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

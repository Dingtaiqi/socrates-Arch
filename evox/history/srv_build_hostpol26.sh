P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol22.img
IMG=/build/out/evox_socrates_system_hostpol26.img
MNT=/mnt/hp26
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
cp -f /build/out/apexd_dsu $MNT/system/bin/apexd
chmod 755 $MNT/system/bin/apexd
python3 - <<"PYEOF"
import os
pi = "/mnt/hp26/system/bin/init"; os.setxattr(pi, "security.selinux", b"u:object_r:init_exec:s0\x00")
pa = "/mnt/hp26/system/bin/apexd"; os.setxattr(pa, "security.selinux", b"u:object_r:apexd_exec:s0\x00")
print("init kmsg.log str:", b"kmsg.log" in open(pi,"rb").read())
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

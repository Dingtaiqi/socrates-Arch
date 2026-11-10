P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol19.img
IMG=/build/out/evox_socrates_system_hostpol20.img
MNT=/mnt/hp20
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 - <<"PYEOF"
import os
p = "/mnt/hp20/system/bin/init"
os.setxattr(p, "security.selinux", b"u:object_r:init_exec:s0\x00")
d = open(p, "rb").read()
print("fs_step in init:", b"fs_step" in d, "| watchdog:", b"dsu_boot_watchdog" in d)
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

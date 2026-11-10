P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
INIT_BIN=/build/out/init_dsu
[ -f "$INIT_BIN" ] || { echo "ERROR: missing init"; exit 1; }
SRC=/build/out/evox_socrates_system_hostpol14.img
IMG=/build/out/evox_socrates_system_hostpol15.img
MNT=/mnt/hp15
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f $INIT_BIN $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 - <<"PYEOF"
import os
p="/mnt/hp15/system/bin/init"
os.setxattr(p,"security.selinux",b"u:object_r:init_exec:s0\x00")
print("init xattr:", os.getxattr(p,"security.selinux"))
d=open(p,"rb").read()
print("trace code present:", b"trace.log" in d, "| m_wait_skipped:", b"m_wait_skipped" in d)
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

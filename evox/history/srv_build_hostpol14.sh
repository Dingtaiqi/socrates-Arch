P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
INIT_BIN=/build/out/init_dsu
[ -f "$INIT_BIN" ] || { echo "ERROR: $INIT_BIN missing"; exit 1; }
SRC=/build/out/evox_socrates_system_hostpol13.img
IMG=/build/out/evox_socrates_system_hostpol14.img
MNT=/mnt/hp14
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 原 init 大小/hash ====="
ls -la $MNT/system/bin/init
sha256sum $MNT/system/bin/init | cut -c1-24
echo "===== 新 init ====="
ls -la $INIT_BIN
sha256sum $INIT_BIN | cut -c1-24
file $INIT_BIN | head -1

cp -f $INIT_BIN $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 - <<"PYEOF"
import os
p="/mnt/hp14/system/bin/init"
os.setxattr(p,"security.selinux",b"u:object_r:init_exec:s0\x00")
print("init xattr:", os.getxattr(p,"security.selinux"))
# 确认诊断补丁字符串存在
d=open(p,"rb").read()
print("marker string in new init:", b"m_wait_skipped" in d, "| old userdebug patched:", b"Xserdebug_plat_sepolicy" in d)
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

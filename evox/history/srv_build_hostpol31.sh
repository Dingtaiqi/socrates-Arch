P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol30.img
IMG=/build/out/evox_socrates_system_hostpol31.img
MNT=/mnt/hp31
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
python3 - <<"PYEOF"
import os
p = "/mnt/hp31/system/bin/keystore2"
os.setxattr(p, "security.selinux", b"u:object_r:keystore_exec:s0\x00")
print("keystore2 label:", os.getxattr(p, "security.selinux"))
# 顺便确认 keystore_cli_v2 等文件标签正确
for f in ["keystore_cli_v2"]:
    q = "/mnt/hp31/system/bin/" + f
    if os.path.isfile(q):
        print(f, os.getxattr(q, "security.selinux"))
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

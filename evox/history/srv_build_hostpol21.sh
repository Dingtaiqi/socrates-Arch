P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "===== 新编译的 libfs_mgr.so ====="
ls -la /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so
strings -a /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so | grep -c "fs_step" || true

SRC=/build/out/evox_socrates_system_hostpol20.img
IMG=/build/out/evox_socrates_system_hostpol21.img
MNT=/mnt/hp21
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 原 libfs_mgr.so 位置/标签 ====="
find $MNT -name "libfs_mgr.so" 2>/dev/null | head -5
python3 - <<"PYEOF"
import os, glob
for p in glob.glob("/mnt/hp21/system/lib64/libfs_mgr.so"):
    try:
        print(p, "label:", os.getxattr(p, "security.selinux"))
    except Exception as e:
        print(p, "label err:", e)
PYEOF

echo "===== 替换 libfs_mgr.so ====="
for f in $(find $MNT -name "libfs_mgr.so" 2>/dev/null); do
  cp -f /build/evox/out_init/target/product/socrates/system/lib64/libfs_mgr.so "$f"
  chmod 644 "$f"
  echo "replaced: $f"
done
python3 - <<"PYEOF"
import os, glob
for p in glob.glob("/mnt/hp21/system/lib64/libfs_mgr.so"):
    os.setxattr(p, "security.selinux", b"u:object_r:system_lib_file:s0\x00")
    d = open(p, "rb").read()
    print("new .so has fs_step:", b"fs_step" in d, "| label:", os.getxattr(p, "security.selinux"))
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

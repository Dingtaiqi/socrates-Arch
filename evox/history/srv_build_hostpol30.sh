P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol28.img
IMG=/build/out/evox_socrates_system_hostpol30.img
MNT=/mnt/hp30
OS4=/home/qinghuo/os4key
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 1. 替换 init（若已构建）====="
if [ -f /build/out/init_dsu ]; then
  cp -f /build/out/init_dsu $MNT/system/bin/init
  chmod 755 $MNT/system/bin/init
  echo "init replaced"
fi

echo "===== 2. 替换 keystore2 ====="
cp -f $OS4/bin/keystore2 $MNT/system/bin/keystore2
chmod 755 $MNT/system/bin/keystore2
ls -la $MNT/system/bin/keystore2

echo "===== 3. 替换 keystore2 相关库（不动框架库）====="
python3 - <<"PYEOF"
import os, glob, shutil
src_dir = "/home/qinghuo/os4key/lib64"
dst_dir = "/mnt/hp30/system/lib64"
exclude = {
 "libc++.so","libc.so","libm.so","libdl.so","libdl_android.so","libbase.so",
 "libbinder.so","libbinder_ndk.so","liblog.so","libutils.so","libcutils.so",
 "libhardware.so","libhidlbase.so","libvndksupport.so","libselinux.so",
 "libsqlite.so","libcrypto.so","libpcre2.so","libapexsupport.so",
 "libpackagelistparser.so",
}
replaced = []
for p in sorted(glob.glob(src_dir + "/*.so")):
    name = os.path.basename(p)
    if name in exclude:
        continue
    dst = os.path.join(dst_dir, name)
    shutil.copyfile(p, dst)
    os.chmod(dst, 0o644)
    replaced.append(name)
print("replaced libs:", len(replaced))
for n in replaced:
    print("  ", n)
PYEOF

echo "===== 4. 设置标签 ====="
python3 - <<"PYEOF"
import os, glob
p = "/mnt/hp30/system/bin/keystore2"
os.setxattr(p, "security.selinux", b"u:object_r:keystore2_exec:s0\x00")
print("keystore2 label:", os.getxattr(p, "security.selinux"))
n = 0
for f in glob.glob("/mnt/hp30/system/lib64/*.so"):
    try:
        cur = os.getxattr(f, "security.selinux")
    except Exception:
        cur = None
    if cur is None:
        os.setxattr(f, "security.selinux", b"u:object_r:system_lib_file:s0\x00")
        n += 1
print("lib labels fixed:", n)
PYEOF

sync
df -k $MNT | tail -1
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

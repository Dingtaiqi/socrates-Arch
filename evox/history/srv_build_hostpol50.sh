P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "== 编译 zygote wrapper =="
aarch64-linux-gnu-gcc -O2 -static -o /tmp/app_process64_wrap /home/qinghuo/zygote_wrapper.c
ls -la /tmp/app_process64_wrap

echo "== hostpol50 = hostpol49 + wrapper =="
SRC=/build/out/evox_socrates_system_hostpol49.img
IMG=/build/out/evox_socrates_system_hostpol50.img
MNT=/mnt/hp50b
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
df -k $MNT | tail -1
# 原始 app_process64 改名
mv $MNT/system/bin/app_process64 $MNT/system/bin/app_process64.real
cp /tmp/app_process64_wrap $MNT/system/bin/app_process64
chmod 755 $MNT/system/bin/app_process64 $MNT/system/bin/app_process64.real
python3 - <<"PYEOF"
import os
for f in ["/mnt/hp50b/system/bin/app_process64",
          "/mnt/hp50b/system/bin/app_process64.real"]:
    os.setxattr(f, "security.selinux", b"u:object_r:zygote_exec:s0\x00")
    print(f, os.path.getsize(f), os.getxattr(f, "security.selinux"))
PYEOF
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

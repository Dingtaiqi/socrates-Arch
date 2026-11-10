P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
echo "== 编译 wrapper2 =="
aarch64-linux-gnu-gcc -O2 -static -o /tmp/app_process64_wrap2 /home/qinghuo/zygote_wrapper2.c
ls -la /tmp/app_process64_wrap2

SRC=/build/out/evox_socrates_system_hostpol49.img
IMG=/build/out/evox_socrates_system_hostpol52.img
MNT=/mnt/hp52
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/hp52/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

mv $MNT/system/bin/app_process64 $MNT/system/bin/app_process64.real
cp /tmp/app_process64_wrap2 $MNT/system/bin/app_process64
chmod 755 $MNT/system/bin/app_process64 $MNT/system/bin/app_process64.real
python3 - <<"PYEOF"
import os
for f in ["/mnt/hp52/system/bin/app_process64",
          "/mnt/hp52/system/bin/app_process64.real"]:
    os.setxattr(f, "security.selinux", b"u:object_r:zygote_exec:s0\x00")
    print(f, os.path.getsize(f))
PYEOF
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

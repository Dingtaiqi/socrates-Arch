P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol61.img
IMG=/build/out/evox_socrates_system_hostpol62.img
MNT=/mnt/hp62
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) 复制 app_process64 为 app_process64x（规避 KernelSU 可能的路径 hook）
cp -a $MNT/system/bin/app_process64 $MNT/system/bin/app_process64x
python3 -c "import os; os.setxattr(\"/mnt/hp62/system/bin/app_process64x\",\"security.selinux\",b\"u:object_r:zygote_exec:s0\x00\")"

# 2) init.zygote64.rc 改命令
python3 - <<"PYEOF"
import io
p = "/mnt/hp62/system/etc/init/hw/init.zygote64.rc"
s = io.open(p, encoding="utf-8").read()
s = s.replace("service zygote /system/bin/app_process64 ", "service zygote /system/bin/app_process64x ")
io.open(p, "w", encoding="utf-8").write(s)
print(s.split(chr(10))[0])

# 3) zzz_dsu_zygote_dbg.rc 同步改（stdio_to_kmsg 覆盖版）
p2 = "/mnt/hp62/system/etc/init/zzz_dsu_zygote_dbg.rc"
s2 = io.open(p2, encoding="utf-8").read()
s2 = s2.replace("service zygote /system/bin/app_process64 ", "service zygote /system/bin/app_process64x ")
io.open(p2, "w", encoding="utf-8").write(s2)
print(s2.split(chr(10))[1])
PYEOF

# 4) 删掉 runner rc（避免干扰）
rm -f $MNT/system/etc/init/zzz_dsu_zygote_runner.rc $MNT/system/bin/zygote_runner

# 5) 修复 /dev/kmsg 标签（stdio_to_kmsg 需要）
cat >> $MNT/system/etc/init/zzz_dsu_override4.rc <<"EOF"

on early-init
    restorecon /dev/kmsg
    restorecon /dev/kmsg_debug
EOF

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

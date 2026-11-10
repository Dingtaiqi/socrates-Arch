#!/bin/bash
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol58.img
IMG=/build/out/evox_socrates_system_hostpol59.img
MNT=/mnt/hp59
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; os.setxattr(\"/mnt/hp59/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"

# 新的 app_process 调试 service（stdio_to_kmsg）
cat > $MNT/system/etc/init/zzz_dsu_appproc_dbg.rc <<"EOF"
# [dsu-port] 用正式 service 跑 app_process，stdio_to_kmsg 捕获 stderr 到内核日志
service zygote_dbg /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg
    class late_start
    user root
    group root readproc reserved_disk
    socket zygote_dbg stream 660 root system
    disabled
    oneshot
    stdio_to_kmsg
    seclabel u:r:zygote:s0

on zygote-start
    start zygote_dbg
EOF
# 移除 override4 里旧的直接 exec 行
python3 - <<"PYEOF"
import io, re
p = "/mnt/hp59/system/etc/init/zzz_dsu_override4.rc"
s = io.open(p, encoding="utf-8").read()
s = re.sub(r"# \[dsu-port\] 直接跑 app_process64.*\Z", "", s, flags=re.S)
io.open(p, "w", encoding="utf-8").write(s.rstrip() + "\n")
print("override4 cleaned")
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

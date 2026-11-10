P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol3.img
IMG=/build/out/evox_socrates_system_hostpol4.img
MNT=/mnt/hp4
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

echo "===== 1. 注释 wait_for_prop 阻塞（保留原行注释）====="
python3 - <<PYEOF
import re
rc = "/mnt/hp4/system/etc/init/hw/init.rc"
lines = open(rc, encoding="utf-8", errors="replace").read().splitlines(True)
out = []
patched = 0
for ln in lines:
    s = ln.lstrip()
    if s.startswith("wait_for_prop") and not s.startswith("#"):
        indent = ln[:len(ln)-len(s)]
        out.append(indent + "# [dsu-port] " + s)
        patched += 1
    else:
        out.append(ln)
open(rc, "w", encoding="utf-8").writelines(out)
print("wait_for_prop commented:", patched)
PYEOF

echo "===== 2. 追加分阶段标记 + 诊断服务 ====="
cat >> $RC <<"EOF"

# ==== DSU port: stage markers (patched) ====
on early-init
    write /metadata/gsi/dsu/stage_early_init 1

on init
    write /metadata/gsi/dsu/stage_init 1

on post-fs
    write /metadata/gsi/dsu/stage_post_fs 1

on late-fs
    write /metadata/gsi/dsu/stage_late_fs 1

on post-fs-data
    write /metadata/gsi/dsu/stage_post_fs_data 1

on zygote-start
    write /metadata/gsi/dsu/stage_zygote_start 1

on early-boot
    write /metadata/gsi/dsu/stage_early_boot 1

on boot
    write /metadata/gsi/dsu/stage_boot 1

service gsi_dump /system/bin/sh /system/bin/gsi_dump.sh
    class core
    user root
    oneshot
    disabled

on early-init
    start gsi_dump

on boot
    start gsi_dump
EOF

echo "===== 3. 验证 ====="
grep -n "wait_for_prop" $RC | head -8
echo "--- stage markers ---"
grep -n "stage_" $RC | head -10
echo "--- tail ---"
tail -8 $RC

sync
df -k $MNT | tail -1
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -3
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG
'

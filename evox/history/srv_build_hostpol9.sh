P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol8.img
IMG=/build/out/evox_socrates_system_hostpol9.img
MNT=/mnt/hp9
cp -f $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

echo "===== 修复 exec 语法 ====="
grep -n "exec /system/bin" $RC | head -5
python3 - <<"PYEOF"
p = "/mnt/hp9/system/etc/init/hw/init.rc"
s = open(p, encoding="utf-8", errors="replace").read()
s = s.replace("    exec /system/bin/sh /system/bin/probe_dsu.sh",
              "    exec - root root -- /system/bin/sh /system/bin/probe_dsu.sh")
s = s.replace("    exec /system/bin/diag_probe",
              "    # [dsu-port] removed invalid exec /system/bin/diag_probe")
open(p, "w", encoding="utf-8").write(s)
print("patched")
PYEOF
grep -n "exec - root root -- /system/bin/sh\|removed invalid exec" $RC | head -5
tail -10 $RC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

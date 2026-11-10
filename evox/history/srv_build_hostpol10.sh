P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol8.img
IMG=/build/out/evox_socrates_system_hostpol10.img
MNT=/mnt/hp10
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

echo "===== 1. 修复 exec 语法 ====="
python3 - <<"PYEOF"
p = "/mnt/hp10/system/etc/init/hw/init.rc"
s = open(p, encoding="utf-8", errors="replace").read()
s = s.replace("    exec /system/bin/sh /system/bin/probe_dsu.sh",
              "    exec - root root -- /system/bin/sh /system/bin/probe_dsu.sh")
s = s.replace("    exec /system/bin/diag_probe",
              "    # [dsu-port] removed invalid exec")
open(p, "w", encoding="utf-8").write(s)
print("init.rc patched")
PYEOF

echo "===== 2. 重设所有新文件的 SELinux 标签 ====="
python3 - <<"PYEOF"
import os
files = ["/system/bin/probe_dsu.sh", "/system/bin/gsi_dump.sh", "/system/bin/diag_probe"]
for f in files:
    p = "/mnt/hp10" + f
    if not os.path.exists(p):
        print("MISSING", p); continue
    os.setxattr(p, "security.selinux", b"u:object_r:shell_exec:s0\x00")
    print("%-32s %s" % (f, os.getxattr(p, "security.selinux")))
# 顺便验证关键系统文件标签未损坏
for f in ["/system/bin/init", "/system/bin/sh", "/system/bin/toybox", "/system/etc/init/hw/init.rc"]:
    p = "/mnt/hp10" + f
    try:
        v = os.getxattr(p, "security.selinux")
    except Exception as e:
        v = "ERR %s" % e
    print("%-32s %s" % (f, v))
PYEOF

echo "===== 3. 验证 exec 行 ====="
grep -n "exec - root root -- /system/bin/sh\|removed invalid exec" $RC | head -3
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

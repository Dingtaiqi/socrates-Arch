P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol10.img
IMG=/build/out/evox_socrates_system_hostpol12.img
MNT=/mnt/hp12
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.rc

python3 - <<"PYEOF"
p = "/mnt/hp12/system/etc/init/hw/init.rc"
s = open(p, encoding="utf-8", errors="replace").read()
marker = """# ==== DSU port: early init-trigger marker (prepended) ====
on init
    write /metadata/gsi/dsu/m_init_first 1
    write /metadata/gsi/dsu/m_init_second 1

"""
s = marker + s
open(p, "w", encoding="utf-8").write(s)
print("prepended")
PYEOF
head -8 $RC
echo "..."
grep -n "^on init" $RC | head -5

python3 - <<"PYEOF"
import os
for f in ["/system/bin/probe_dsu.sh","/system/bin/gsi_dump.sh","/system/bin/diag_probe"]:
    p="/mnt/hp12"+f
    os.setxattr(p,"security.selinux",b"u:object_r:shell_exec:s0\x00")
print("xattr ok")
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

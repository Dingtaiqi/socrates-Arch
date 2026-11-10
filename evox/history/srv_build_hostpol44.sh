P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol43.img
IMG=/build/out/evox_socrates_system_hostpol44.img
MNT=/mnt/hp44
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

python3 - <<"PYEOF"
import io
p = "/mnt/hp44/system/etc/init/hw/init.rc"
s = io.open(p, encoding="utf-8", errors="replace").read()
before = s
s = s.replace("import /system/etc/init/hw/init.${ro.zygote}.rc",
              "import /system/etc/init/hw/init.zygote64.rc  # [dsu-port] hardcode (ro.zygote=zygote64_32 from host vendor, no 64_32 rc in image)")
s = s.replace("import /system/etc/init/hw/init.boringssl.${ro.zygote}.rc",
              "import /system/etc/init/hw/init.boringssl.zygote64.rc  # [dsu-port] hardcode")
io.open(p, "w", encoding="utf-8").write(s)
print("changed:", before != s)
for ln in s.splitlines():
    if "import /system/etc/init/hw/init.zygote" in ln or "boringssl.zygote" in ln:
        print("  ", ln.strip()[:150])
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

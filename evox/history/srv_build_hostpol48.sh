P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol47.img
IMG=/build/out/evox_socrates_system_hostpol48.img
MNT=/mnt/hp48
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

python3 - <<"PYEOF"
import io
p = "/mnt/hp48/system/etc/init/hw/init.rc"
s = io.open(p, encoding="utf-8", errors="replace").read()
old = "    # [dsu-port] wait_for_prop apexd.status activated"
new = "    wait_for_prop apexd.status activated  # [dsu-port] restored (apexd works now)"
if old in s:
    s = s.replace(old, new, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("restored apexd wait")
else:
    print("pattern not found")

io.open(p, encoding="utf-8", errors="replace").read()
for ln in s.splitlines():
    if "wait_for_prop" in ln:
        print("  ", ln.strip()[:120])
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

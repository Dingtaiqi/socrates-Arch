P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol26.img
IMG=/build/out/evox_socrates_system_hostpol27.img
MNT=/mnt/hp27
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 替换 init ====="
cp -f /build/out/init_dsu $MNT/system/bin/init
chmod 755 $MNT/system/bin/init
python3 -c "import os; p=\"/mnt/hp27/system/bin/init\"; os.setxattr(p,\"security.selinux\",b\"u:object_r:init_exec:s0\x00\"); print(\"init kmsg reader:\", b\"/dev/kmsg\" in open(p,2**20 and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and p and \"rb\").read() if False else b\"/dev/kmsg\" in open(p,\"rb\").read())"

echo "===== 修补 netbpfload.rc（注释 wait_for_prop bpf.progs_loaded）====="
python3 - <<"PYEOF"
import io
p = "/mnt/hp27/system/etc/init/netbpfload.rc"
s = io.open(p, encoding="utf-8", errors="replace").read()
lines = s.splitlines(True)
out = []
patched = 0
for ln in lines:
    if "wait_for_prop bpf.progs_loaded" in ln and "#" not in ln.split("wait_for_prop")[0]:
        indent = ln[:len(ln)-len(ln.lstrip())]
        out.append(indent + "# [dsu-port] " + ln.lstrip())
        patched += 1
    else:
        out.append(ln)
io.open(p, "w", encoding="utf-8").writelines(out)
print("netbpfload wait_for_prop commented:", patched)
PYEOF
grep -n "wait_for_prop\|bpf.progs_loaded" $MNT/system/etc/init/netbpfload.rc
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

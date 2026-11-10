P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol22.img
IMG=/build/out/evox_socrates_system_hostpol24.img
MNT=/mnt/hp24
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 1. 先解压 art 到 /tmp（镜像外）====="
python3 - <<"PYEOF"
import os, zipfile, shutil
capex = "/mnt/hp24/system/apex/com.android.art.capex"
out = "/tmp/art.apex"
with zipfile.ZipFile(capex) as z:
    ent = [n for n in z.namelist() if "original_apex" in n][0]
    label = os.getxattr(capex, "security.selinux")
    with z.open(ent) as src, open(out, "wb") as dst:
        shutil.copyfileobj(src, dst, 1024*1024)
    open("/tmp/art.label", "wb").write(label)
print("extracted:", os.path.getsize(out))
PYEOF

echo "===== 2. 删除 art.capex 释放空间 ====="
rm -f $MNT/system/apex/com.android.art.capex $MNT/system/apex/com.android.art.apex
rm -f $MNT/system/bin/diag_probe $MNT/system/bin/gsi_dump.sh $MNT/system/bin/probe_dsu.sh 2>/dev/null || true
df -k $MNT | tail -1

echo "===== 3. 写入 art.apex ====="
cp /tmp/art.apex $MNT/system/apex/com.android.art.apex
chmod 644 $MNT/system/apex/com.android.art.apex
python3 - <<"PYEOF"
import os
p = "/mnt/hp24/system/apex/com.android.art.apex"
label = open("/tmp/art.label","rb").read()
if not label.endswith(b"\x00"):
    label += b"\x00"
os.setxattr(p, "security.selinux", label)
print("art.apex:", os.path.getsize(p), "label:", os.getxattr(p,"security.selinux"))
PYEOF
df -k $MNT | tail -1
ls -la $MNT/system/apex/ | grep art
rm -f /tmp/art.apex /tmp/art.label
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

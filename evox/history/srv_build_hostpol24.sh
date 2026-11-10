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
df -k $MNT | tail -1

echo "===== 删除调试文件释放空间 ====="
rm -f $MNT/system/bin/diag_probe $MNT/system/bin/gsi_dump.sh $MNT/system/bin/probe_dsu.sh 2>/dev/null || true
df -k $MNT | tail -1

echo "===== 转换 com.android.art.capex -> art.apex ====="
python3 - <<"PYEOF"
import os, zipfile
capex = "/mnt/hp24/system/apex/com.android.art.capex"
out = "/mnt/hp24/system/apex/com.android.art.apex"
with zipfile.ZipFile(capex) as z:
    names = z.namelist()
    print("entries:", names[:5])
    ent = [n for n in names if "original_apex" in n][0]
    label = os.getxattr(capex, "security.selinux")
    with z.open(ent) as src, open(out, "wb") as dst:
        import shutil as sh
        sh.copyfileobj(src, dst, 1024*1024)
    os.chmod(out, 0o644)
    os.setxattr(out, "security.selinux", label)
    os.unlink(capex)
    print("art apex:", os.path.getsize(out), "label:", label)
PYEOF
df -k $MNT | tail -1
ls -la $MNT/system/apex/com.android.art.*
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol22.img
IMG=/build/out/evox_socrates_system_hostpol23.img
MNT=/mnt/hp23
NEWSIZE=2147483648

echo "===== 1. 复制并扩容 ====="
cp -a $SRC $IMG
truncate -s $NEWSIZE $IMG
e2fsck -f -y $IMG 2>&1 | tail -2
resize2fs $IMG 2>&1 | tail -3
ls -la $IMG

echo "===== 2. 挂载并转换 .capex -> .apex ====="
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
df -h $MNT | tail -1
python3 - <<"PYEOF"
import os, zipfile, glob, shutil
apex_dir = "/mnt/hp23/system/apex"
capex = sorted(glob.glob(apex_dir + "/*.capex"))
print("capex count:", len(capex))
ok = 0; fail = []
for c in capex:
    base = os.path.basename(c)[:-6]  # strip .capex
    out = os.path.join(apex_dir, base + ".apex")
    try:
        with zipfile.ZipFile(c) as z:
            names = z.namelist()
            ent = None
            for n in names:
                if "original_apex" in n:
                    ent = n; break
            if ent is None:
                fail.append((c, "no original_apex entry: %s" % names[:5])); continue
            # label from capex
            try:
                label = os.getxattr(c, "security.selinux")
            except Exception:
                label = b"u:object_r:system_file:s0\x00"
            with z.open(ent) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst, 1024*1024)
            os.chmod(out, 0o644)
            os.setxattr(out, "security.selinux", label)
            os.unlink(c)
            ok += 1
            print("OK", base, os.path.getsize(out))
    except Exception as e:
        fail.append((c, str(e)))
print("converted:", ok, "failed:", len(fail))
for f in fail[:10]:
    print("FAIL", f)
PYEOF

echo "===== 3. 检查空间/文件 ====="
df -h $MNT | tail -1
ls $MNT/system/apex/ | head -8
echo "..."
ls $MNT/system/apex/*.capex 2>/dev/null | wc -l
ls $MNT/system/apex/*.apex 2>/dev/null | wc -l
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG
'

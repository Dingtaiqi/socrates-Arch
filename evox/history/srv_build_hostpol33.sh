P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol32.img
IMG=/build/out/evox_socrates_system_hostpol33.img
MNT=/mnt/hp33
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
df -k $MNT | tail -1

echo "===== 1. 释放空间（删除两个 GMS 可选应用）====="
rm -rf $MNT/system/priv-app/DocumentsUIGoogle $MNT/system/priv-app/AppDataBackup 2>/dev/null || true
df -k $MNT | tail -1

echo "===== 2. 转换失败的两个 capex -> apex（先解压到 /tmp）====="
python3 - <<"PYEOF"
import os, zipfile, shutil, glob
MNT = "/mnt/hp33"
targets = ["com.android.art", "com.android.media.swcodec"]
for name in targets:
    capex = os.path.join(MNT, "system/apex", name + ".capex")
    if not os.path.exists(capex):
        print(name, "capex not present, skip")
        continue
    out = "/tmp/" + name + ".apex"
    with zipfile.ZipFile(capex) as z:
        ent = [n for n in z.namelist() if "original_apex" in n][0]
        label = os.getxattr(capex, "security.selinux")
        with z.open(ent) as src, open(out, "wb") as dst:
            shutil.copyfileobj(src, dst, 1024*1024)
    print(name, "extracted", os.path.getsize(out))
    open("/tmp/" + name + ".label", "wb").write(label)
PYEOF

echo "===== 3. 删除 capex 并写入 apex ====="
rm -f $MNT/system/apex/com.android.art.capex $MNT/system/apex/com.android.media.swcodec.capex
rm -f $MNT/system/apex/com.android.art.apex $MNT/system/apex/com.android.media.swcodec.apex
df -k $MNT | tail -1
for n in com.android.art com.android.media.swcodec; do
  cp /tmp/$n.apex $MNT/system/apex/$n.apex
  chmod 644 $MNT/system/apex/$n.apex
done
python3 - <<"PYEOF"
import os
for name in ["com.android.art", "com.android.media.swcodec"]:
    p = "/mnt/hp33/system/apex/" + name + ".apex"
    label = open("/tmp/" + name + ".label", "rb").read()
    if not label.endswith(b"\x00"):
        label += b"\x00"
    os.setxattr(p, "security.selinux", label)
    print(name, os.path.getsize(p), os.getxattr(p, "security.selinux"))
PYEOF
rm -f /tmp/com.android.*.apex /tmp/com.android.*.label
df -k $MNT | tail -1

echo "===== 4. 替换 init（若构建完成）====="
if [ -f /build/out/init_dsu ]; then
  cp -f /build/out/init_dsu $MNT/system/bin/init
  chmod 755 $MNT/system/bin/init
  python3 -c "import os; os.setxattr(\"/mnt/hp33/system/bin/init\",\"security.selinux\",b\"u:object_r:init_exec:s0\x00\")"
  echo "init updated"
else
  echo "WARN: init_dsu not built yet, keep old"
fi

echo "===== 5. 停 misight 死循环的 rc ====="
mkdir -p $MNT/system/etc/init
cat > $MNT/system/etc/init/zzz_dsu_override3.rc <<"EOF"
# [dsu-port] Xiaomi misight 服务在 DSU 下崩溃循环，停掉它
on init
    stop vendor.mi_misight
on boot
    stop vendor.mi_misight
on property:init.svc.vendor.mi_misight=running
    stop vendor.mi_misight
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override3.rc
python3 -c "import os; os.setxattr(\"/mnt/hp33/system/etc/init/zzz_dsu_override3.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
cat /mnt/hp33/system/etc/init/zzz_dsu_override3.rc

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

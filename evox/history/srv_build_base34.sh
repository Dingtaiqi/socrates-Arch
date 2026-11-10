#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base32.img
IMG=/build/out/evox_socrates_base34.img
MNT=/mnt/base34
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) init.rc 加 classpath 遮罩（同 base33）
RC=$MNT/system/etc/init/hw/init.rc
python3 - <<"PYEOF"
p="/mnt/base34/system/etc/init/hw/init.rc"
s=open(p).read()
if "dsu-hide-compatible-classpath" not in s:
    old="    exec_start derive_classpath\n    load_exports /data/system/environ/classpath"
    new="""    # [dsu-hide-compatible-classpath] 遮住宿主 A14 兼容 ART APEX 的 classpaths
    mount tmpfs tmpfs /apex/com.android.art.compatible/etc/classpaths
    exec_start derive_classpath
    load_exports /data/system/environ/classpath"""
    assert old in s, "classpath anchor missing"
    s=s.replace(old,new,1)
    open(p,"w").write(s)
    print("init.rc classpath patched")
else:
    print("classpath already patched")
PYEOF

# 2) zygote rc 恢复直连 app_process64，去掉 wrapper 和 stdio_to_kmsg（fd 泄漏）
ZRC=$MNT/system/etc/init/hw/init.zygote64_32.rc
python3 - <<"PYEOF"
p="/mnt/base34/system/etc/init/hw/init.zygote64_32.rc"
s=open(p).read()
s=s.replace("service zygote /system/bin/dsu_zygote_wrap.sh -Xzygote",
            "service zygote /system/bin/app_process64 -Xzygote")
# 去掉 stdio_to_kmsg 行（避免 fd 泄漏到 system_server）
lines=[l for l in s.split("\n") if l.strip()!="stdio_to_kmsg"]
s="\n".join(lines)
open(p,"w").write(s)
print("zygote rc reverted")
PYEOF
echo "== zygote rc =="
head -14 $ZRC
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base29.img#" gen_diff3.py > gen_diff34.py
python3 gen_diff34.py /build/out/evox_socrates_base34.img /home/qinghuo/base34.diff
chown qinghuo /home/qinghuo/base34.diff
ls -la /home/qinghuo/base34.diff
'

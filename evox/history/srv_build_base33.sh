#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base32.img
IMG=/build/out/evox_socrates_base33.img
MNT=/mnt/base33
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

RC=$MNT/system/etc/init/hw/init.rc
python3 - <<"PYEOF"
p = "/mnt/base33/system/etc/init/hw/init.rc"
s = open(p).read()
if "dsu-hide-compatible-classpath" in s:
    print("already patched")
else:
    old = "    exec_start derive_classpath\n    load_exports /data/system/environ/classpath"
    new = """    # [dsu-hide-compatible-classpath] 宿主 /system_ext 的 com.android.art.compatible
    # (A14 兼容 APEX) 的 bootclasspath.pb 指向自己 APEX 之外的 jar，A17 derive_classpath
    # 会 CHECK 失败直接 abort -> BOOTCLASSPATH 为空 -> zygote abort。
    # 用 tmpfs 遮住它的 classpaths 目录，让 derive_classpath 跳过它。
    mount tmpfs tmpfs /apex/com.android.art.compatible/etc/classpaths
    exec_start derive_classpath
    load_exports /data/system/environ/classpath"""
    if old in s:
        s = s.replace(old, new, 1)
        open(p, "w").write(s)
        print("init.rc patched")
    else:
        print("ANCHOR NOT FOUND")
PYEOF
grep -n -B2 -A3 "dsu-hide-compatible-classpath" $RC | head -12
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base29.img#" gen_diff3.py > gen_diff33.py
python3 gen_diff33.py /build/out/evox_socrates_base33.img /home/qinghuo/base33.diff
chown qinghuo /home/qinghuo/base33.diff
ls -la /home/qinghuo/base33.diff
'

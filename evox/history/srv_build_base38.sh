#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base37.img
IMG=/build/out/evox_socrates_base38.img
MNT=/mnt/base38
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
RC=$MNT/system/etc/init/hw/init.zygote64_32.rc
cp -a $RC /build/out/base38_zygote_rc.orig
python3 - <<PYEOF
import io
p="/mnt/base38/system/etc/init/hw/init.zygote64_32.rc"
s=io.open(p,encoding="utf-8").read()
needle="--zygote --start-system-server --socket-name=zygote"
repl="--zygote --start-system-server --socket-name=zygote --abi-list=arm64-v8a,armeabi-v7a,armeabi"
if needle in s:
    s=s.replace(needle,repl,1)
    io.open(p,"w",encoding="utf-8").write(s)
    print("rc patched: abi-list added")
else:
    print("NEEDLE NOT FOUND")
PYEOF
grep -n "abi-list" $RC
python3 -c "import os; os.setxattr(\"$RC\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")" || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base37.img#" gen_diff3.py > gen_diff38.py
python3 gen_diff38.py /build/out/evox_socrates_base38.img /home/qinghuo/base38.diff
chown qinghuo /home/qinghuo/base38.diff
ls -la /home/qinghuo/base38.diff
'

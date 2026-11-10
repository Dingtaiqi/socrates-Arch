P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol56.img
IMG=/build/out/evox_socrates_system_hostpol57.img
MNT=/mnt/hp57
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
# 修正 rc：去掉 $?（避免 init 属性展开报错）
python3 - <<"PYEOF"
import io
p = "/mnt/hp57/system/etc/init/zzz_dsu_override4.rc"
s = io.open(p, encoding="utf-8").read()
old = s
s = s.replace(
  "/system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg >/dev/null 2>/metadata/gsi/dsu/appproc_dbg.log; echo exit=$? >>/metadata/gsi/dsu/appproc_dbg.log",
  "/system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg >/dev/null 2>/metadata/gsi/dsu/appproc_dbg.log; echo DONE >>/metadata/gsi/dsu/appproc_dbg.log")
io.open(p, "w", encoding="utf-8").write(s)
print("rc fixed:", s != old)
print(s[-500:])
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

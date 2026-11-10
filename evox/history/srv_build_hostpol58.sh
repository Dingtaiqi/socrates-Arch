P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol57.img
IMG=/build/out/evox_socrates_system_hostpol58.img
MNT=/mnt/hp58
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
python3 - <<"PYEOF"
import io
p = "/mnt/hp58/system/etc/init/zzz_dsu_override4.rc"
s = io.open(p, encoding="utf-8").read()
old = s
import re
# 用直接 exec app_process64 替换 shell 版本
s = re.sub(r"on zygote-start\n.*?(?=\n# |\Z)", "", s, flags=re.S)
s = s.rstrip() + """

# [dsu-port] 直接跑 app_process64 捕获真实错误（stderr 进 init 的 kmsg）
on zygote-start
    exec - root root -- /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote_dbg
"""
io.open(p, "w", encoding="utf-8").write(s)
print("rc rewritten")
print(s[-400:])
PYEOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

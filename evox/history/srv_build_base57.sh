#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_base56.img
IMG=/build/out/evox_socrates_base57.img
MNT=/mnt/b57
umount $MNT 2>/dev/null || true
rm -f $IMG
cp -a $SRC $IMG
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "== b57 相机方案：cameraserver 延迟到 boot_completed 之后再启动 =="
echo "--- before ---"
cat $MNT/system/etc/init/cameraserver.rc
python3 - "$MNT" <<PYEOF
import sys, io
mnt = sys.argv[1]
p = mnt + '/system/etc/init/cameraserver.rc'
s = io.open(p, encoding='utf-8').read()
if 'disabled' not in s:
    s = s.replace('    class main\n', '    class main\n    disabled\n', 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
    print('added disabled to cameraserver.rc')
else:
    print('disabled already present')
# 延迟启动 trigger
q = mnt + '/system/etc/init/zzz_camera_delayed.rc'
io.open(q, 'w', encoding='utf-8', newline='\n').write('''# [dsu-cam] b57: cameraserver 延迟到 boot_completed 之后再启动，
# 避开 system_server 在 WindowManagerService.initPolicy 里查闪光灯相机时
# 与 cameraserver（等 activity 服务）形成的循环死锁。
on property:sys.boot_completed=1
    start cameraserver
''')
print('wrote zzz_camera_delayed.rc')
PYEOF
chmod 0644 $MNT/system/etc/init/zzz_camera_delayed.rc
python3 -c "import os; os.setxattr(\"/mnt/b57/system/etc/init/zzz_camera_delayed.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
python3 -c "import os; os.setxattr(\"/mnt/b57/system/etc/init/cameraserver.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
echo "--- after ---"
cat $MNT/system/etc/init/cameraserver.rc
cat $MNT/system/etc/init/zzz_camera_delayed.rc
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base54b.img#" gen_diff3.py > gen_diff_b57.py
python3 gen_diff_b57.py /build/out/evox_socrates_base57.img /home/qinghuo/base57.diff
chown qinghuo /home/qinghuo/base57.diff
ls -la /home/qinghuo/base57.diff
'

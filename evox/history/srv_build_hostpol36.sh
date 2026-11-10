P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol35.img
IMG=/build/out/evox_socrates_system_hostpol36.img
MNT=/mnt/hp36
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 覆盖屏蔽 Xiaomi 崩溃循环服务 ====="
cat > $MNT/system/etc/init/zzz_dsu_override3.rc <<"EOF"
# [dsu-port] 屏蔽在 DSU 下崩溃循环的 Xiaomi/厂商服务（overridden with /system/bin/true, disabled）
service vendor.mi_misight /system/bin/true
    class core
    user root
    group root
    disabled
    override

service misight /system/bin/true
    class core
    user root
    group root
    disabled
    override

service mqsas /system/bin/true
    class core
    user root
    group root
    disabled
    override

service vendor.mi_dpmd /system/bin/true
    class core
    user root
    group root
    disabled
    override

service dpmd /system/bin/true
    class core
    user root
    group root
    disabled
    override
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override3.rc
python3 -c "import os; os.setxattr(\"/mnt/hp36/system/etc/init/zzz_dsu_override3.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
cat $MNT/system/etc/init/zzz_dsu_override3.rc

echo "===== 顺便看一下 host 上还有哪些 Xiaomi 服务 rc ====="
ls /mnt/hp36/system/etc/init/ 2>/dev/null | head -20
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

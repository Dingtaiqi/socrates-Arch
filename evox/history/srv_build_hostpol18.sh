P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol17.img
IMG=/build/out/evox_socrates_system_hostpol18.img
MNT=/mnt/hp18
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

cat > $MNT/system/etc/init/zzz_dsu_override.rc <<"EOF"
# DSU port override: 64-bit-only system image cannot run vendor 32-bit boringssl self-test.
# init keeps the FIRST service definition for a duplicate name; /system/etc/init is parsed
# before /vendor/etc/init, so these no-op definitions replace the vendor ones and avoid
# reboot_on_failure reboot loops under DSU.
service boringssl_self_test32_vendor /system/bin/true
    user root
    group root
    oneshot

service boringssl_self_test64_vendor /system/bin/true
    user root
    group root
    oneshot
EOF
chmod 644 $MNT/system/etc/init/zzz_dsu_override.rc
python3 - <<"PYEOF"
import os
p = "/mnt/hp18/system/etc/init/zzz_dsu_override.rc"
os.setxattr(p, "security.selinux", b"u:object_r:system_file:s0\x00")
print("rc xattr:", os.getxattr(p, "security.selinux"))
PYEOF
ls -la $MNT/system/etc/init/zzz_dsu_override.rc
cat $MNT/system/etc/init/zzz_dsu_override.rc
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
IMG=/build/out/evox_socrates_system_hostpol3.img
MNT=/mnt/hp3
cp /build/out/evox_socrates_system_hostpol2.img $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
df -k $MNT | tail -1

echo "===== 1. 嵌套 system_ext 策略 ====="
mkdir -p $MNT/system/system_ext/etc/selinux/mapping
tar -xf /home/qinghuo/host_ext_selinux.tar -C $MNT/system/system_ext/etc/selinux/
ls $MNT/system/system_ext/etc/selinux/ | head -8

echo "===== 2. 嵌套 product 策略 ====="
mkdir -p $MNT/system/product/etc/selinux/mapping
tar -xf /home/qinghuo/host_prd_selinux.tar -C $MNT/system/product/etc/selinux/
ls $MNT/system/product/etc/selinux/ | head -8

echo "===== 3. patch init userdebug 字符串 ====="
INIT=$MNT/system/bin/init
grep -abo "userdebug_plat_sepolicy" $INIT | head -3
for off in $(grep -abo "userdebug_plat_sepolicy" $INIT | cut -d: -f1); do
  printf "X" | dd of="$INIT" bs=1 seek="$off" conv=notrunc 2>/dev/null
  echo "patched offset $off"
done
grep -c "userdebug_plat_sepolicy" $INIT || true
grep -abo "Xserdebug_plat_sepolicy" $INIT | head -2

echo "===== 4. prop.default adb 调试 ====="
PROPD=$MNT/system/etc/prop.default
if [ -f "$PROPD" ]; then
  grep -nE "ro.adb.secure|ro.debuggable" $PROPD || true
  sed -i "s/^ro.adb.secure=.*/ro.adb.secure=0/" $PROPD
  sed -i "s/^ro.debuggable=.*/ro.debuggable=1/" $PROPD
  grep -nE "ro.adb.secure|ro.debuggable" $PROPD || true
else
  echo "no prop.default"
fi

echo "===== 5. 诊断脚本 + init.rc 服务 ====="
cat > $MNT/system/bin/diag_dump.sh <<"EOF"
#!/system/bin/sh
mkdir -p /metadata/gsi/dsu
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 8
  getprop > /metadata/gsi/dsu/diag_props_$i.txt 2>&1
  cat /proc/mounts > /metadata/gsi/dsu/diag_mounts_$i.txt 2>&1
  dmesg > /metadata/gsi/dsu/diag_dmesg_$i.txt 2>&1
  logcat -d -v threadtime > /metadata/gsi/dsu/diag_logcat_$i.txt 2>&1
  logcat -d -b crash -v threadtime > /metadata/gsi/dsu/diag_crash_$i.txt 2>&1
  sync
done
EOF
chmod 750 $MNT/system/bin/diag_dump.sh
cat >> $MNT/system/etc/init/hw/init.rc <<"EOF"

# ==== DSU diagnostics (patched) ====
service diag_dump /system/bin/sh /system/bin/diag_dump.sh
    class core
    user root
    oneshot
    disabled

on early-init
    start diag_dump

on boot
    start diag_dump
EOF
tail -14 $MNT/system/etc/init/hw/init.rc

echo "===== 6. 空间检查 + 卸载 ====="
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -3
ls -la $IMG
chown qinghuo $IMG
sha256sum $IMG
'

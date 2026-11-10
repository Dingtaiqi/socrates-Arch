P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
IMG=/build/out/evox_socrates_system_hostpol3.img
MNT=/mnt/hp3
cp -f /build/out/evox_socrates_system_hostpol2.img $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
df -k $MNT | tail -1

echo "===== 1. patch init userdebug 字符串 ====="
INIT=$MNT/system/bin/init
for off in $(grep -abo "userdebug_plat_sepolicy" $INIT | cut -d: -f1); do
  printf "X" | dd of="$INIT" bs=1 seek="$off" conv=notrunc 2>/dev/null
  echo "patched offset $off"
done
grep -abo "Xserdebug_plat_sepolicy" $INIT | head -2 || true

echo "===== 2. prop.default 调试属性 ====="
PROPD=$MNT/system/etc/prop.default
if [ -f "$PROPD" ]; then
  grep -nE "ro.adb.secure|ro.debuggable" $PROPD || true
  sed -i "s/^ro.adb.secure=.*/ro.adb.secure=0/" $PROPD
  sed -i "s/^ro.debuggable=.*/ro.debuggable=1/" $PROPD
  grep -nE "ro.adb.secure|ro.debuggable" $PROPD || true
else
  echo "no prop.default"
fi

echo "===== 3. 诊断脚本 ====="
cat > $MNT/system/bin/gsi_dump.sh <<"EOF"
#!/system/bin/sh
mkdir -p /metadata/gsi/dsu
echo 5 > /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null
echo 100 > /proc/sys/kernel/hung_task_warnings 2>/dev/null
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  sleep 5
  getprop > /metadata/gsi/dsu/diag_props.txt 2>&1
  cat /proc/mounts > /metadata/gsi/dsu/diag_mounts.txt 2>&1
  dmesg > /metadata/gsi/dsu/diag_dmesg_$i.txt 2>&1
  logcat -d -v threadtime > /metadata/gsi/dsu/diag_logcat_$i.txt 2>&1
  logcat -d -b crash -v threadtime > /metadata/gsi/dsu/diag_crash_$i.txt 2>&1
  ps -A > /metadata/gsi/dsu/diag_ps_$i.txt 2>&1
  sync
done
EOF
chmod 750 $MNT/system/bin/gsi_dump.sh
cat >> $MNT/system/etc/init/hw/init.rc <<"EOF"

# ==== DSU diagnostics (patched) ====
service gsi_dump /system/bin/sh /system/bin/gsi_dump.sh
    class core
    user root
    oneshot
    disabled

on early-init
    start gsi_dump

on boot
    start gsi_dump
EOF
tail -14 $MNT/system/etc/init/hw/init.rc

echo "===== 4. 空间/卸载/检查 ====="
df -k $MNT | tail -1
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -3
chown qinghuo $IMG
ls -la $IMG
sha256sum $IMG
'

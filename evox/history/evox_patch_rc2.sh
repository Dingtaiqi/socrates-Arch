#!/system/bin/sh
setenforce 0
umount /mnt/evox 2>/dev/null
rm -rf /mnt/evox; mkdir -p /mnt/evox
dmctl delete evox_sys 2>/dev/null
sh /data/local/tmp/evox_map.sh >/dev/null 2>&1
sleep 1
mount -t ext4 -o rw $(dmctl getpath evox_sys) /mnt/evox
echo "mount_rc=$?"
cp -f /data/local/tmp/evox_init2.rc /mnt/evox/system/etc/init/hw/init.rc
echo "write_rc=$?"
ls -la /mnt/evox/system/etc/init/hw/init.rc
grep -c 'ev_pfd' /mnt/evox/system/etc/init/hw/init.rc
sync
umount /mnt/evox
echo "umount_rc=$?"
dmctl delete evox_sys 2>/dev/null
dmctl delete evox_scratch 2>/dev/null
setenforce 1
rm -rf /metadata/gsi/dsu/ev_* /metadata/gsi/dsu/probe_* /metadata/gsi/dsu/a15_*
echo -n "0" > /metadata/gsi/dsu/install_status
echo -n "1" > /metadata/gsi/dsu/one_shot_boot
echo -n "dsu" > /metadata/gsi/dsu/active
rm -f /metadata/gsi/dsu/booted
sync
echo PATCHED_ARMED

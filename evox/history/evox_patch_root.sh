#!/system/bin/sh
setenforce 0
umount /mnt/evox 2>/dev/null
rm -rf /mnt/evox; mkdir -p /mnt/evox
dmctl delete evox_sys 2>/dev/null
sh /data/local/tmp/evox_map.sh >/dev/null 2>&1
sleep 1
DEV=$(dmctl getpath evox_sys)
echo "DEV=$DEV"
mount -t ext4 -o rw "$DEV" /mnt/evox
echo "mount_rc=$?"
echo "== before =="
su -c "getfattr -n security.selinux /mnt/evox" 2>&1 | head -4
su -c "setfattr -n security.selinux -v u:object_r:rootfs:s0 /mnt/evox" 2>&1
echo "setfattr_rc=$?"
su -c "getfattr -n security.selinux /mnt/evox" 2>&1 | head -4
echo "== other root entries labels =="
for d in system system_ext product vendor odm data metadata; do
  echo -n "/$d: "; su -c "getfattr -n security.selinux /mnt/evox/$d 2>/dev/null | grep security" 2>&1 | head -1
done
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

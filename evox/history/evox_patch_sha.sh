#!/system/bin/sh
# Make EvoX init accept the host odm precompiled policy (avoids the failing on-device compile).
setenforce 0
umount /mnt/evox/new 2>/dev/null
rm -rf /mnt/evox; mkdir -p /mnt/evox
dmctl delete pchk 2>/dev/null
sh /data/local/tmp/evox_map.sh >/dev/null 2>&1
sleep 1
DEV=$(dmctl getpath evox_sys)
echo "DEV=$DEV"
mount -t ext4 -o rw "$DEV" /mnt/evox
echo "mount_rc=$?"
NEW=/mnt/evox
printf '36020cb9ac40874c5deb66d3fa3057fd36a70e2eb26ba07a384afcd13d144cb2\n' > $NEW/system/etc/selinux/plat_sepolicy_and_mapping.sha256
printf '75fd7239e1e747def7a725da3d3b938b0e3504dce2195567565cc59b0f4b0e67\n' > $NEW/system_ext/etc/selinux/system_ext_sepolicy_and_mapping.sha256
printf 'f107e91327e0f279f019ab395ef4ebcea8ba9ca7df2b7bd089148026dd50c35c\n' > $NEW/product/etc/selinux/product_sepolicy_and_mapping.sha256
echo "write_rc=$?"
cat $NEW/system/etc/selinux/plat_sepolicy_and_mapping.sha256
cat $NEW/system_ext/etc/selinux/system_ext_sepolicy_and_mapping.sha256
cat $NEW/product/etc/selinux/product_sepolicy_and_mapping.sha256
sync
umount $NEW
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

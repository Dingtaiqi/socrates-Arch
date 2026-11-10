#!/system/bin/sh
setenforce 0
umount /mnt/evox 2>/dev/null
rm -rf /mnt/evox; mkdir -p /mnt/evox
dmctl delete evox_sys 2>/dev/null
sh /data/local/tmp/evox_map.sh >/dev/null 2>&1
sleep 1
mount -t ext4 -o rw $(dmctl getpath evox_sys) /mnt/evox
echo "mount_rc=$?"
echo "== netbpfload.rc before =="
cat /mnt/evox/system/etc/init/netbpfload.rc
echo "== disable all reboot_on_failure lines in image rc files =="
LIST=/data/local/tmp/bpf_rc_list.txt
grep -rl 'reboot_on_failure' /mnt/evox/system/etc/init /mnt/evox/system_ext/etc/init /mnt/evox/product/etc/init 2>/dev/null > $LIST
cat $LIST
while read f; do
  sed -i 's/^\([[:space:]]*\)reboot_on_failure/\1#reboot_on_failure/' "$f" 2>/dev/null
  echo "patched $f rc=$?"
done < $LIST
echo "== netbpfload.rc after =="
cat /mnt/evox/system/etc/init/netbpfload.rc
echo "== verify remaining active reboot_on_failure =="
grep -rn '^[[:space:]]*reboot_on_failure' /mnt/evox/system/etc/init /mnt/evox/system_ext/etc/init /mnt/evox/product/etc/init 2>/dev/null | head -5
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

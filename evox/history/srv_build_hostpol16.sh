P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
SRC=/build/out/evox_socrates_system_hostpol14.img
IMG=/build/out/evox_socrates_system_hostpol16.img
MNT=/mnt/hp16
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

echo "===== 禁用可疑 LineageOS/AOSP 特有 early-init 动作 ====="
mkdir -p $MNT/system/etc/init/disabled_dsu
for f in kcmdlinemodprobe.rc kcmdlinectrl.rc dsu_2nd.rc; do
  if [ -f $MNT/system/etc/init/$f ]; then
    mv $MNT/system/etc/init/$f $MNT/system/etc/init/disabled_dsu/$f
    echo "disabled: $f"
  fi
done
ls $MNT/system/etc/init/ | head -20
echo "--- disabled dir ---"
ls $MNT/system/etc/init/disabled_dsu/

echo "===== 保留我们的标记（确认 init.rc 里 still 有）====="
grep -c "stage_early_init\|m_init_first" $MNT/system/etc/init/hw/init.rc || true
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -2
chown qinghuo $IMG
sha256sum $IMG
'

#!/bin/bash
set -uo pipefail
H=/home/qinghuo
SRC=/build/out/evox_socrates_base40.img
SPEC=$H/spec_features
IMG=/build/out/_feat.img
EXPECT=63a3de922bf20a8e01d5f6fed6788a79da84f13474bd9194227735b56a680a2d

echo "===== A. PREP FEATURE SPEC ====="
rm -rf "$SPEC"
umask 022
mkdir -p "$SPEC/add/system/etc" "$SPEC/rc/system/etc/init"
echo "hello mkimg test" > "$SPEC/add/system/etc/mkimg_test.txt"
chmod 644 "$SPEC/add/system/etc/mkimg_test.txt"
touch -d "2026-01-02 03:04:05" "$SPEC/add/system/etc/mkimg_test.txt"
printf 'on post-fs\n    write /metadata/gsi/dsu/mkimg_test 1\n' > "$SPEC/rc/system/etc/init/zzz_mkimg_test.rc"
echo "12345678" > /dev/null
echo /system/evox_product/NotExistForTest > "$SPEC/del.txt"
NEWSIZE=1105199104
echo "$NEWSIZE" > "$SPEC/size.txt"
echo "size.txt=$NEWSIZE  src_size=$(stat -c%s "$SRC")"

echo "===== B. RUN TOOL (grow + add + del + rc) ====="
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' bash "$H/srv_mkimg.sh" "$SRC" "$IMG" "$SPEC" >/tmp/mk_feat.log 2>&1
echo "rc=$?"; grep -E '扩容|MKDIR|COPY|DEL|SKIP|RC |DST 大小|DST sha256|DIFF 大小|ERROR' /tmp/mk_feat.log

echo "===== C. VERIFY FEATURE RESULT ====="
echo "--- fs size ---"
dumpe2fs -h "$IMG" 2>/dev/null | grep -E 'Block count|Block size|Free blocks'
echo "--- file inode ---"
debugfs -R 'stat /system/etc/mkimg_test.txt' "$IMG" 2>/dev/null | grep -E 'Inode:|Mode|Size:|atime|mtime'
echo "--- file content ---"
debugfs -R 'cat /system/etc/mkimg_test.txt' "$IMG" 2>/dev/null
echo "--- rc file ---"
debugfs -R 'cat /system/etc/init/zzz_mkimg_test.rc' "$IMG" 2>/dev/null
echo "--- selinux xattr ---"
debugfs -R 'ea_list /system/etc/init/zzz_mkimg_test.rc' "$IMG" 2>/dev/null
echo "--- rc inode mode ---"
debugfs -R 'stat /system/etc/init/zzz_mkimg_test.rc' "$IMG" 2>/dev/null | grep -E 'Mode|User:|Size:'
echo "--- diff file ---"
ls -la "$IMG.diff" 2>/dev/null
echo "--- mochk: mounted read-only verification ---"
mkdir -p /mnt/featverify
mount -o loop,ro "$IMG" /mnt/featverify 2>/dev/null && {
  echo "re-read file: $(cat /mnt/featverify/system/etc/mkimg_test.txt)"
  getfattr -d -m - /mnt/featverify/system/etc/init/zzz_mkimg_test.rc 2>/dev/null | head -3
  stat -c 'mode=%a uid=%u gid=%g mtime=%y' /mnt/featverify/system/etc/mkimg_test.txt
  df -h /mnt/featverify | tail -1
  umount /mnt/featverify
} || echo "MOUNT_RO_FAIL"

echo "===== D. IDEMPOTENT RE-RUN (pinned base42) ====="
rm -f /build/out/_base42t2.img /build/out/_base42t2.img.diff
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' bash "$H/srv_mkimg.sh" /build/out/evox_socrates_base41b.img /build/out/_base42t2.img "$H/spec_base42" >/tmp/mk_pin2.log 2>&1
echo "rerun_rc=$?"; grep -E 'DST sha256|DST 大小|DIFF 大小' /tmp/mk_pin2.log
sha256sum /build/out/_base42t2.img
[ "$(sha256sum /build/out/_base42t2.img | awk '{print $1}')" = "$EXPECT" ] && echo "IDEMPOTENT_RERUN=HIT" || echo "IDEMPOTENT_RERUN=MISS"

echo "===== E. CLEANUP FEATURE TEMP ====="
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' rm -f "$IMG" "$IMG.diff" /build/out/_base42t2.img /build/out/_base42t2.img.diff
ls -la /build/out/base42t.img /build/out/base42t.img.diff 2>/dev/null | awk '{print $5, $9}'
df -h /build | tail -1
echo "===== FEATURE TEST DONE $(date +%T) ====="

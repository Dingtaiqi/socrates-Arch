set -eu
[ -f /etc/arch-release ]
[ "$(findmnt -n -o FSTYPE /)" = overlay ]
out=/dev/kde_dsu/rootfs-export
mkdir -p "$out"
[ ! -e "$out/arch-kde-60hz-v3.erofs" ]
[ ! -f "$out/build.log" ] || cp "$out/build.log" "$out/build-previous.log"
cat >"$out/build.sh" <<'BUILD'
set -eu
out=/dev/kde_dsu/rootfs-export
mkfs.erofs -zlz4hc,level=9 -C4096 -x-1 \
 --exclude-path=dev --exclude-path=proc --exclude-path=sys \
 --exclude-path=run --exclude-path=tmp --exclude-path=mnt \
 --exclude-path=root --exclude-path=home --exclude-path=data \
 --exclude-path=var/cache/pacman/pkg --exclude-path=var/log \
 "$out/arch-kde-60hz-v3.erofs" /
fsck.erofs "$out/arch-kde-60hz-v3.erofs"
sha256sum "$out/arch-kde-60hz-v3.erofs" >"$out/SHA256SUMS"
stat -c 'ROOTFS_SNAPSHOT_BYTES=%s' "$out/arch-kde-60hz-v3.erofs"
cat "$out/SHA256SUMS"
printf 'ROOTFS_SNAPSHOT_COMPLETE\n'
BUILD
nohup timeout -k 10 600 nice -n 19 taskset -c 0,1 sh "$out/build.sh" </dev/null >"$out/build.log" 2>&1 &
echo "$!" >"$out/build.pid"
sleep 2
kill -0 "$(cat "$out/build.pid")"
printf 'ROOTFS_SNAPSHOT_STARTED\n'
printf 'INIT EXECUTABLE\n'; readlink /proc/1/exe
ps -eo pid,ppid,comm,args | grep -E 'native_init|/system/bin/init' | grep -v grep || true

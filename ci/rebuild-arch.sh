#!/usr/bin/env bash
# Rebuild the native init and desktop launcher in an owned image copy.
# The pinned baseline contains the proven EROFS rootfs and vendor runtime.
set -euo pipefail
image=$(realpath -- "${1:?image required}")
test -f "$image"
test ! -L "$1"
test "$(stat -c %s "$image")" = 3221225472
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
e2fsck -fn "$image"
aarch64-linux-gnu-gcc --version
dpkg-query -W e2fsprogs erofs-utils gcc-aarch64-linux-gnu
aarch64-linux-gnu-gcc -O2 -static -Wall -Wextra -o "$work/minit" arch/minit_kde.c
aarch64-linux-gnu-readelf -h "$work/minit" | grep -q 'Machine:.*AArch64'
if aarch64-linux-gnu-readelf -l "$work/minit" | grep -q INTERP; then
    echo 'Init must be static' >&2
    exit 1
fi
cp arch/kde-start.sh "$work/launcher"
debugfs -R "dump /system/etc/arch/persist.uuid $work/persist.uuid" "$image"
test "$(cat "$work/persist.uuid")" = fad4bd59-96f1-4c6c-8791-d31c87b82264
# Read back every write: debugfs can report command errors with exit code zero.
replace_file() {
    local source=$1 target=$2
    debugfs -w -R "rm $target" "$image"
    debugfs -w -R "write $source $target" "$image"
    debugfs -w -R "set_inode_field $target mode 0100755" "$image"
    debugfs -R "dump $target $work/readback" "$image"
    cmp "$source" "$work/readback"
    rm "$work/readback"
}
replace_file "$work/minit" /system/bin/init
replace_file "$work/minit" /native_init
replace_file "$work/launcher" /system/etc/arch/kde-start.sh
debugfs -R "dump /system/arch-rootfs.erofs $work/rootfs.erofs" "$image"
printf '%s  %s\n' 7afa94d0b226a1a22c79fb82ca2c12256d258d5257c5eb8dec7685281f070023 "$work/rootfs.erofs" | sha256sum -c -
fsck.erofs "$work/rootfs.erofs"
e2fsck -fn "$image"
echo 'OFFLINE REBUILD COMPLETE: requires a separate device test.'

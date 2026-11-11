#!/usr/bin/env bash
# Build a restored snapshot in a new Ubuntu root, without mounting an old checkout.
# Requires root, x86-64 Linux, ~64 GiB RAM and sufficient local disk.
set -euo pipefail
test "$(id -u)" = 0
test "$(uname -m)" = x86_64
recipe=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(realpath -m -- "${1:?Usage: sudo bash evox/fresh-build.sh NEW_WORK_DIR}")
test "$work" != /
test "$work" != "$recipe"
if [ "${EVOLUTION_FRESH_MOUNT_NS:-0}" != 1 ]; then
    exec unshare --mount --fork --propagation private \
        env EVOLUTION_FRESH_MOUNT_NS=1 BUILD_JOBS="${BUILD_JOBS:-16}" \
        bash "$recipe/evox/fresh-build.sh" "$work"
fi
if [ -d "$work" ] && [ -n "$(ls -A "$work")" ] && [ ! -f "$work/.evox-fresh-workspace" ]; then
    echo 'Refusing to adopt an unrelated directory' >&2; exit 2
fi
mkdir -p "$work"
printf '%s\n' 'socrates-evox-fresh-v1' >"$work/.evox-fresh-workspace"
exec 9>"$work/run.lock"
flock -n 9
python3 - "$work" <<'PY'
import shutil,sys
from pathlib import Path
free=shutil.disk_usage(sys.argv[1]).free
memory=int(next(l.split()[1] for l in Path('/proc/meminfo').read_text().splitlines() if l.startswith('MemTotal:')))*1024
if memory < 60*1024**3: raise SystemExit('At least 60 GiB usable host RAM required')
if not (Path(sys.argv[1])/'ubuntu/.dependencies-ready').exists() and free < 320*1024**3:
    raise SystemExit('At least 320 GiB free required for this fixed snapshot and a fresh output tree')
print('FRESH_HOST_FREE_GIB',round(free/1024**3,2),flush=True)
PY
root="$work/ubuntu"
mkdir -p "$root" "$work/downloads" "$work/build" "$work/logs"
base=ubuntu-base-22.04.5-base-amd64.tar.gz
sha=242cd8898b33ea806ef5f13b1076ed7c76f9f989d18384452f7166692438ff1a
if [ ! -f "$work/downloads/$base" ]; then
    curl --fail --location --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/$base" \
        -o "$work/downloads/$base.download"
    printf '%s  %s\n' "$sha" "$work/downloads/$base.download" | sha256sum -c -
    mv "$work/downloads/$base.download" "$work/downloads/$base"
fi
printf '%s  %s\n' "$sha" "$work/downloads/$base" | sha256sum -c -
if [ ! -f "$root/.base-ready" ]; then
    test -z "$(ls -A "$root")"
    tar --numeric-owner -xpf "$work/downloads/$base" -C "$root"
    touch "$root/.base-ready"
fi
mkdir -p "$root"/{dev,proc,sys,workspace,recipes,tmp}
mount --rbind /dev "$root/dev"
mount --make-rslave "$root/dev"
# Some hosts expose /dev/shm as root-only. Python's multiprocessing semaphore
# creation must work for the unprivileged builder inside this private namespace.
mkdir -p "$root/dev/shm"
mount -t tmpfs -o mode=1777,nosuid,nodev,size=2G tmpfs "$root/dev/shm"
mount -t proc proc "$root/proc"
mount --rbind /sys "$root/sys"
mount --make-rslave "$root/sys"
mount --bind "$work/build" "$root/workspace"
mount --bind "$recipe" "$root/recipes"
mount -o remount,bind,ro "$root/recipes"
chmod 1777 "$root/tmp"
rm -f -- "$root/etc/resolv.conf"
cp -L /etc/resolv.conf "$root/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' >"$root/usr/sbin/policy-rc.d"
chmod 755 "$root/usr/sbin/policy-rc.d"
if [ ! -f "$root/.dependencies-ready" ]; then
    cat >"$root/etc/apt/sources.list" <<'APT'
deb http://archive.ubuntu.com/ubuntu jammy main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu jammy-updates main universe multiverse restricted
deb http://security.ubuntu.com/ubuntu jammy-security main universe multiverse restricted
APT
    chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -c '
        set -e
        apt-get update
        apt-get install -y --no-install-recommends \
          ca-certificates bc bison build-essential ccache cpio curl flex fontconfig \
          g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
          lib32ncurses-dev lib32readline-dev lib32z1-dev libc6-dev-i386 libelf-dev \
          libgl1-mesa-dev liblz4-tool libncurses5 libssl-dev libtinfo5 \
          libx11-dev libxml2 libxml2-utils lzop make openssl pngcrush \
          python3 python-is-python3 rsync schedtool squashfs-tools \
          util-linux x11proto-core-dev xsltproc zip unzip zlib1g-dev zstd
        groupadd -g 1000 builder
        useradd -m -u 1000 -g 1000 -s /bin/bash builder
        apt-get clean
        touch /.dependencies-ready
    '
fi
chown 1000:1000 "$work/build"
chroot "$root" dpkg-query -W >"$work/logs/container-packages.tsv"
chroot "$root" /usr/sbin/runuser -u builder -- python3 -c \
    'import multiprocessing; p=multiprocessing.Pool(2); assert p.map(abs, [-1,-2]) == [1,2]; p.close(); p.join()'
ulimit -n 65536
exec python3 "$recipe/evox/run-fresh-build.py" "$work" "$recipe"

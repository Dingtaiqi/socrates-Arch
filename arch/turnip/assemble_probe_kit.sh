#!/usr/bin/env bash
# Run only on the established build host; all writes stay in the task directory.
set -euo pipefail
export LC_ALL=C
work=/home/qinghuo/kde_dsu_20261109
sysroot=/build/arch/rootfs-weston
kit=$work/probe-kit
stage=$kit/stage/opt/kde-dsu
mkdir -p "$stage/tools/bin" "$stage/tools/lib" "$stage/licenses" "$stage/evidence"
cp -a "$work/turnip-output-gcc12/stage/opt/kde-dsu/turnip-26.2.6" "$stage/"
cp -a "$work/mesa-26.2.6/licenses" "$stage/licenses/mesa"
cp "$work/mesa-26.2.6/docs/license.rst" "$stage/licenses/mesa-license.rst"
for package in "$work"/diagnostic-pkgs/*.pkg.tar.xz; do
    name=$(basename "$package" .pkg.tar.xz)
    unpack=$kit/packages/$name
    mkdir -p "$unpack"
    tar -xJf "$package" -C "$unpack"
    if [ -d "$unpack/usr/share/licenses" ]; then
        cp -a "$unpack/usr/share/licenses/." "$stage/licenses/"
    fi
    if [ -f "$unpack/usr/bin/vulkaninfo" ]; then
        cp "$unpack/usr/bin/vulkaninfo" "$stage/tools/bin/"
    fi
    if [ -d "$unpack/usr/lib" ]; then
        find "$unpack/usr/lib" -maxdepth 1 \( -name 'libvulkan.so*' -o -name 'libxcb-keysyms.so*' \) \
            -exec cp -a -t "$stage/tools/lib/" {} +
    fi
done
"$work/toolchain/usr/bin/aarch64-linux-gnu-gcc-12" \
    --sysroot="$sysroot" -B"$work/target-bin/" \
    -O2 -Wall -Wextra -Werror "$work/egl_zink_probe.c" \
    -L"$sysroot/usr/lib" -Wl,-rpath-link,"$sysroot/usr/lib" \
    -lEGL -lGLESv2 -o "$stage/tools/bin/egl_zink_probe"
cp "$work/run_turnip_probe.sh" "$stage/tools/bin/"
chmod 755 "$stage/tools/bin/run_turnip_probe.sh"
bash -n "$stage/tools/bin/run_turnip_probe.sh"
for binary in vulkaninfo egl_zink_probe; do
    /usr/bin/qemu-aarch64-static -L "$sysroot" "$sysroot/usr/lib/ld-linux-aarch64.so.1" \
        --library-path "$stage/tools/lib:$sysroot/usr/lib" \
        --list "$stage/tools/bin/$binary" >"$kit/$binary-loader.txt"
    ! grep -E 'not found|version .* not found' "$kit/$binary-loader.txt"
done
cp "$work/diagnostic-pkgs/manifest.json" "$stage/evidence/package-manifest.json"
cp "$work/turnip-output-gcc12/build-options.json" "$stage/evidence/"
cp "$kit/"*-loader.txt "$stage/evidence/"
cp "$work/egl_zink_probe.c" "$stage/evidence/"
cd "$kit/stage"
find opt -type f ! -path '*/evidence/files-SHA256SUMS' -print0 | sort -z | \
    xargs -0 sha256sum >"$stage/evidence/files-SHA256SUMS"
tar -czf "$kit/turnip-kgsl-dsu-probe.tar.gz" opt
cd "$kit"
sha256sum turnip-kgsl-dsu-probe.tar.gz | tee SHA256SUMS
printf 'Prepared isolated device probe kit; not yet executed on the phone.\n'

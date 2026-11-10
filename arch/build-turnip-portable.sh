#!/usr/bin/env bash
# Inputs are restored from the public compiler/sysroot kit, without a phone.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
inputs=$(realpath -- "${1:?Usage: build-turnip-portable.sh INPUTS_DIR OUTPUT_DIR}")
output=${2:?Output directory required}
test ! -e "$output"
mkdir -p "$output"
output=$(realpath -- "$output")
sysroot="$inputs/sysroot"
test -f "$sysroot/usr/bin/wayland-scanner"
test -x "$inputs/toolchain/usr/bin/aarch64-linux-gnu-gcc-12"
for tool in qemu-aarch64-static pkg-config aarch64-linux-gnu-as aarch64-linux-gnu-ld; do command -v "$tool" >/dev/null; done
mkdir "$output/bin" "$output/target-bin" "$output/host-pc"
for tool in as ld ar nm objdump objcopy strip ranlib; do
    ln -s "$(command -v "aarch64-linux-gnu-$tool")" "$output/target-bin/$tool"
done
export PYTHONPATH="$inputs/hostpy"
export SOCRATES_SYSROOT="$sysroot"
cat >"$output/bin/meson" <<'TOOL'
#!/bin/sh
exec python3 -m mesonbuild.mesonmain "$@"
TOOL
cat >"$output/bin/wayland-scanner" <<'TOOL'
#!/bin/sh
exec qemu-aarch64-static -L "$SOCRATES_SYSROOT" "$SOCRATES_SYSROOT/usr/bin/wayland-scanner" "$@"
TOOL
chmod 755 "$output/bin/meson" "$output/bin/wayland-scanner"
ln -s "$inputs/hostpy/bin/ninja" "$output/bin/ninja"
ln -s "$inputs/hostpy/cmake/data/bin/cmake" "$output/bin/cmake"
export PATH="$output/bin:$inputs/host-tools/bin:$PATH"
export PKG_CONFIG_PATH="$output/host-pc"
export PKG_CONFIG_PATH_FOR_BUILD="$output/host-pc"
python3 - "$inputs" "$output" <<'PY'
from pathlib import Path
import sys
i,o=map(Path,sys.argv[1:]);s=i/'sysroot'
(o/'host-pc/wayland-scanner.pc').write_text(f'''wayland_scanner={o}/bin/wayland-scanner
Name: Wayland Scanner
Description: Pinned target scanner through QEMU
Version: 1.26.0
''')
c=[str(i/'toolchain/usr/bin/aarch64-linux-gnu-gcc-12'),f'--sysroot={s}',f'-B{o}/target-bin/']
cpp=[str(i/'toolchain/usr/bin/aarch64-linux-gnu-g++-12'),*c[1:]]
(o/'cross.ini').write_text(f'''[binaries]
c = {c!r}
cpp = {cpp!r}
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '{s}'
pkg_config_libdir = ['{s}/usr/lib/pkgconfig', '{s}/usr/share/pkgconfig']
needs_exe_wrapper = true
[built-in options]
c_link_args = ['-L{s}/usr/lib', '-Wl,-rpath-link,{s}/usr/lib']
cpp_link_args = ['-L{s}/usr/lib', '-Wl,-rpath-link,{s}/usr/lib']
''')
PY
printf '%s  %s\n' b9436b3e1a8be76fbd4823dc884f90596ab7c6ac5e1867a305e66ffccfb31a92 "$inputs/sources/mesa-26.2.6.tar.xz" | sha256sum -c -
tar -xJf "$inputs/sources/mesa-26.2.6.tar.xz" -C "$output"
if [ -d "$inputs/mesa-packagecache" ]; then
    mkdir -p "$output/mesa-26.2.6/subprojects/packagecache"
    cp "$inputs/mesa-packagecache/"* "$output/mesa-26.2.6/subprojects/packagecache/"
fi
wayland-scanner --version
meson --version
TURNIP_BUILD_JOBS=${TURNIP_BUILD_JOBS:-8} bash "$repo_dir/arch/turnip/build_turnip_kgsl.sh" \
    "$output/mesa-26.2.6" "$output/driver" "$output/cross.ini"

#!/usr/bin/env bash
# Build/stage a KGSL-only Vulkan ICD without replacing system Mesa libraries.
# Usage: build_turnip_kgsl.sh MESA_SOURCE OUTPUT_DIR [MESON_CROSS_FILE]
# Dependencies must already be provided by the isolated build environment.
set -euo pipefail
src=$(realpath "$1")
mkdir -p "$2"
out=$(realpath "$2")
cross=()
if [ -n "${3:-}" ]; then cross=(--cross-file "$(realpath "$3")"); fi
jobs=${TURNIP_BUILD_JOBS:-4}
case "$jobs" in ''|*[!0-9]*) echo 'Invalid TURNIP_BUILD_JOBS' >&2; exit 2;; esac
[ "$jobs" -ge 1 ] && [ "$jobs" -le 16 ]
[ "$(cat "$src/VERSION")" = '26.2.6' ]
prefix=/opt/kde-dsu/turnip-26.2.6

meson setup "$out/build" "$src" "${cross[@]}" \
    --prefix="$prefix" --libdir=lib --buildtype=release \
    -Db_lto=false -Db_ndebug=true \
    -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl \
    '-Dgallium-drivers=[]' -Dplatforms=wayland \
    -Dglx=disabled -Degl=disabled -Dgbm=disabled \
    -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
    -Dllvm=disabled -Dspirv-tools=disabled \
    -Dlibunwind=disabled -Dvalgrind=disabled \
    -Dbuild-tests=false '-Dtools=[]' '-Dvulkan-layers=[]'
meson introspect "$out/build" --buildoptions >"$out/build-options.json"
meson compile -C "$out/build" -j "$jobs"
DESTDIR="$out/stage" meson install -C "$out/build" --no-rebuild

driver="$out/stage$prefix/lib/libvulkan_freedreno.so"
[ -f "$driver" ]
readelf -h "$driver" | tee "$out/elf-header.txt"
grep -q AArch64 "$out/elf-header.txt"
readelf -d "$driver" >"$out/elf-dynamic.txt"
readelf --version-info "$driver" >"$out/elf-symbol-versions.txt"
python3 - "$driver" <<'PY'
import pathlib,sys
b=pathlib.Path(sys.argv[1]).read_bytes()
assert b'/dev/kgsl-3d0' in b, 'KGSL device path is absent from the built driver'
print('KGSL device path present; GPU execution still requires device testing.')
PY
tar -C "$out/stage" -czf "$out/turnip-26.2.6-kgsl-aarch64.tar.gz" opt
sha256sum "$out/turnip-26.2.6-kgsl-aarch64.tar.gz" >"$out/SHA256SUMS"
printf 'Staged only: %s\n' "$out/turnip-26.2.6-kgsl-aarch64.tar.gz"

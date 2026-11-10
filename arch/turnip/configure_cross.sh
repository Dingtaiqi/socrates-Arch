#!/usr/bin/env bash
set -euo pipefail
work=/home/qinghuo/kde_dsu_20261109
sysroot=/build/arch/rootfs-weston
mkdir -p "$work/bin" "$work/host-pc" "$work/target-bin"
for tool in as ld ar nm objdump objcopy strip ranlib; do
    ln -sf "$(command -v "aarch64-linux-gnu-$tool")" "$work/target-bin/$tool"
done
cat >"$work/bin/wayland-scanner" <<'SCANNER'
#!/bin/sh
exec /usr/bin/qemu-aarch64-static -L /build/arch/rootfs-weston /build/arch/rootfs-weston/usr/bin/wayland-scanner "$@"
SCANNER
chmod 755 "$work/bin/wayland-scanner"
cat >"$work/host-pc/wayland-scanner.pc" <<SCANNER_PC
prefix=$work
wayland_scanner=$work/bin/wayland-scanner
Name: Wayland Scanner
Description: Existing target scanner executed through QEMU for native code generation
Version: 1.26.0
SCANNER_PC
cat >"$work/aarch64-arch-gcc12.ini" <<CROSS
[binaries]
c = ['$work/toolchain/usr/bin/aarch64-linux-gnu-gcc-12', '--sysroot=$sysroot', '-B$work/target-bin/']
cpp = ['$work/toolchain/usr/bin/aarch64-linux-gnu-g++-12', '--sysroot=$sysroot', '-B$work/target-bin/']
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
sys_root = '$sysroot'
pkg_config_libdir = ['$sysroot/usr/lib/pkgconfig', '$sysroot/usr/share/pkgconfig']
needs_exe_wrapper = true
[built-in options]
c_link_args = ['-L$sysroot/usr/lib', '-Wl,-rpath-link,$sysroot/usr/lib']
cpp_link_args = ['-L$sysroot/usr/lib', '-Wl,-rpath-link,$sysroot/usr/lib']
CROSS
export PYTHONPATH="$work/hostpy"
export PATH="$work/hostpy/bin:$work/bin:$PATH"
export PKG_CONFIG_PATH="$work/host-pc"
export PKG_CONFIG_PATH_FOR_BUILD="$work/host-pc"
"$work/bin/wayland-scanner" --version
meson --version
ninja --version
set +e
TURNIP_BUILD_JOBS=12 bash "$work/build_turnip_kgsl.sh" "$work/mesa-26.2.6" "$work/turnip-output-gcc12" "$work/aarch64-arch-gcc12.ini" >"$work/turnip-build-gcc12.log" 2>&1 &
build_pid=$!
while kill -0 "$build_pid" 2>/dev/null; do
    sleep 10
    tail -3 "$work/turnip-build-gcc12.log"
done
wait "$build_pid"
rc=$?
tail -65 "$work/turnip-build-gcc12.log"
printf 'TURNIP_BUILD_EXIT=%s\n' "$rc"
exit "$rc"

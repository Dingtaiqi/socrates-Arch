#!/usr/bin/env bash
# Build the three support components used by the verified desktop launcher.
# The resulting binaries require device validation before replacing a baseline.
set -euo pipefail
out=${1:?output directory required}
cc=${CROSS_CC:-aarch64-linux-gnu-gcc}
mkdir -p "$out/diagnostics" "$out/tools/bin"
"$cc" -O2 -Wall -Wextra -Werror -shared -fPIC \
    -o "$out/diagnostics/libdrm_plane_xrgb_diagnostic.so" arch/gpu/drm_plane_compat.c -ldl
"$cc" -O2 -Wall -Wextra -Werror -shared -fPIC -I/usr/include/libdrm \
    -o "$out/diagnostics/libdrm_timestamp_diagnostic.so" arch/gpu/drm_timestamp_diagnostic.c -ldl
"$cc" -O2 -Wall -Wextra -Werror -static \
    -o "$out/tools/bin/reboot_system" arch/gpu/reboot_system.c
for file in "$out"/diagnostics/*.so "$out/tools/bin/reboot_system"; do
    aarch64-linux-gnu-readelf -h "$file" | grep 'Machine:.*AArch64'
done

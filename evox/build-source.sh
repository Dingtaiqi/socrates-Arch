#!/usr/bin/env bash
# Build the restored current checkout. No device commands or image injection.
set -eo pipefail
source_dir=${1:?Usage: build-source.sh SOURCE_DIR [systemimage|evolution|init|check]}
target=${2:-systemimage}
case "$target" in systemimage|evolution|init|check) ;; *) echo 'Unsupported build target' >&2; exit 2;; esac
source_dir=$(realpath -- "$source_dir")
test -f "$source_dir/build/envsetup.sh"
jobs=${BUILD_JOBS:-8}
case "$jobs" in ''|*[!0-9]*) echo 'Invalid BUILD_JOBS' >&2; exit 2;; esac
test "$jobs" -gt 0
command -v git >/dev/null
command -v python3 >/dev/null
export BUILD_USERNAME=${BUILD_USERNAME:-socrates-builder}
export BUILD_HOSTNAME=${BUILD_HOSTNAME:-socrates-build}
export LC_ALL=C.UTF-8
cd "$source_dir"
# AOSP envsetup accesses unset variables, so do not enable nounset here.
source build/envsetup.sh
lunch lineage_socrates-cp2a-userdebug
test "$(get_build_var TARGET_PRODUCT)" = lineage_socrates
test "$(get_build_var TARGET_BUILD_VARIANT)" = userdebug
if [ "$target" = check ]; then
    echo 'EVOLUTION_BUILD_CONFIGURATION_OK'
    exit 0
fi
mkdir -p source-build-logs
log="source-build-logs/${target}-$(date -u +%Y%m%dT%H%M%SZ).log"
m -j"$jobs" "$target" 2>&1 | tee "$log"
echo "EVOLUTION_BUILD_COMPLETE target=$target log=$source_dir/$log"

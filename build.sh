#!/usr/bin/env bash
# One entry point for restoring and compiling the preserved EvoX checkout.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
action=${1:-help}
case "$action" in
    restore-evox)
        shift
        exec python3 "$repo_dir/evox/restore-source.py" "$@"
        ;;
    evox)
        shift
        destination=${1:?Usage: bash build.sh evox SOURCE_DIR [systemimage|evolution|init|check]}
        if [ ! -e "$destination/.source-restore/RESTORED.json" ]; then
            restore_options=()
            if [ -n "${SOURCE_PARTS_DIR:-}" ]; then
                restore_options=(--local-parts "$SOURCE_PARTS_DIR" --wait-local-parts 14400)
            fi
            python3 "$repo_dir/evox/restore-source.py" "$destination" "${restore_options[@]}"
        fi
        python3 - "$destination/.source-restore/RESTORED.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if not r['complete'] or r['project_count'] != 1265:
    raise SystemExit('Refusing to build an incomplete source restoration')
PY
        exec bash "$repo_dir/evox/build-source.sh" "$@"
        ;;
    arch-support)
        shift
        cd "$repo_dir"
        exec bash arch/build-support.sh "$@"
        ;;
    evox-compat)
        shift
        exec python3 "$repo_dir/evox/dsu/patch-b66.py" "$@"
        ;;
    arch-turnip)
        shift
        inputs=${1:?Usage: bash build.sh arch-turnip INPUTS_WORK_DIR OUTPUT_DIR}
        output=${2:?Output directory required}
        python3 "$repo_dir/arch/restore-build-inputs.py" "$inputs"
        exec bash "$repo_dir/arch/build-turnip-portable.sh" "$inputs/inputs" "$output"
        ;;
    arch-image)
        shift
        exec python3 "$repo_dir/arch/build-image.py" "$@"
        ;;
    *)
        printf '%s\n' \
            'bash build.sh evox /path/to/new/source [systemimage|evolution|init|check]' \
            'bash build.sh restore-evox /path/to/new/source [restore options]' \
            'bash build.sh evox-compat /path/to/pinned-b66.img /path/to/new-compat.img' \
            'bash build.sh arch-support /path/to/output' \
            'bash build.sh arch-turnip /path/to/build-inputs /path/to/output' \
            'PERSIST_UUID=<existing-data-volume-uuid> bash build.sh arch-image /path/to/new.img'
        [ "$action" = help ]
        ;;
esac

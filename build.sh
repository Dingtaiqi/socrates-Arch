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
            python3 "$repo_dir/evox/restore-source.py" "$destination"
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
    *)
        printf '%s\n' \
            'bash build.sh evox /path/to/new/source [systemimage|evolution|init|check]' \
            'bash build.sh restore-evox /path/to/new/source [restore options]' \
            'bash build.sh arch-support /path/to/output'
        [ "$action" = help ]
        ;;
esac

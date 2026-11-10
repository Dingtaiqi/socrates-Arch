#!/usr/bin/env bash
# Run on a recovered source server. Reads the checkout; writes only a new export.
# Review the resulting diffs before uploading: local changes may contain secrets.
set -euo pipefail
top=$(realpath -- "${1:?Android checkout required}")
output=$(realpath -m -- "${2:?new output directory required}")
test -d "$top/.repo"
test ! -e "$output"
case "$output/" in "$top/"*) echo 'Output must be outside the checkout' >&2; exit 2;; esac
command -v repo >/dev/null
mkdir -p "$output/patches" "$output/status"
cd "$top"
repo manifest -r -o "$output/manifest.lock.xml"
export SOURCE_CAPTURE_OUTPUT="$output"
repo forall -c '
set -eu
id=$(printf "%s" "$REPO_PATH" | sha256sum | cut -d " " -f1)
git diff --binary HEAD > "$SOURCE_CAPTURE_OUTPUT/patches/$id.patch"
{
    printf "project=%s\npath=%s\n" "$REPO_PROJECT" "$REPO_PATH"
    git rev-parse HEAD
    git status --porcelain=v1 --untracked-files=no
    printf "\nUntracked filenames only; their contents are not exported:\n"
    git ls-files --others --exclude-standard
} > "$SOURCE_CAPTURE_OUTPUT/status/$id.txt"
'
printf '%s\n' 'Review all patches and untracked filenames before upload; untracked file contents are not included.' > "$output/REVIEW.txt"
echo "Source revision and tracked-change capture complete: $output"

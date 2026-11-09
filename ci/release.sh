#!/usr/bin/env bash
# Create only draft releases; never overwrite a previous build or publish it.
set -euo pipefail
kind=${1:?kind required}
mode=${2:?mode required}
case "$kind:$mode" in arch:archive|arch:rebuild|evox:archive) ;; *) exit 2;; esac
tag="${kind}-${mode}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
export RESULT_KIND=$kind RESULT_MODE=$mode
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
result = {
    'kind': os.environ['RESULT_KIND'], 'mode': os.environ['RESULT_MODE'],
    'source_commit': os.environ['GITHUB_SHA'],
    'run': f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    'device_test': 'historical baseline only' if os.environ['RESULT_MODE'] == 'archive' else 'not tested',
    'scope': 'system image only; no userdata, no partition flashing',
    'sources': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                for base in ('arch', 'ci') for p in Path(base).rglob('*')
                if p.is_file() and '__pycache__' not in str(p)}
}
Path('out/build-record.json').write_text(json.dumps(result, indent=2) + '\n')
PY
tar --exclude='__pycache__' -czf out/build-sources.tar.gz arch ci .github README.md
(cd out; sha256sum ./*.part* ./*.manifest.json build-record.json build-sources.tar.gz build.log > SHA256SUMS)
cat >out/RELEASE-NOTES.md <<EOF
K60 Pro / socrates: $kind, mode=$mode.

System image only. Original device userdata is not included.
archive preserves the pinned baseline SHA256; rebuild needs a new device test.
Download all parts and the matching manifest; restore with ci/bundle.py.
Source revision: $GITHUB_SHA
Run: https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
EOF
gh release create "$tag" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --draft --title "$kind / $mode / $GITHUB_RUN_ID" --notes-file out/RELEASE-NOTES.md
gh release upload "$tag" out/* --repo "$GITHUB_REPOSITORY"
echo "Saved draft release: $tag" >>"$GITHUB_STEP_SUMMARY"

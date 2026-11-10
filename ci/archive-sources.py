"""Archive tracked porting sources and the checksum-pinned upstream Mesa source."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

out = Path('out/source-archive')
out.mkdir(parents=True, exist_ok=False)
lock = json.loads(Path('arch/turnip/source_manifest.json').read_text())
source = out / ('mesa-' + lock['version'] + '.tar.xz')
sha512 = hashlib.sha512()
with urllib.request.urlopen(lock['url'], timeout=90) as response, source.open('xb') as dst:
    while data := response.read(4 * 1024 * 1024):
        sha512.update(data)
        dst.write(data)
if source.stat().st_size != lock['bytes'] or sha512.hexdigest() != lock['sha512']:
    raise SystemExit('Upstream Mesa source does not match the verified lock')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
archive = out / ('socrates-porting-sources-' + commit[:12] + '.tar.gz')
subprocess.run(['git', 'archive', '--format=tar.gz', '-o', str(archive), 'HEAD'], check=True)
server_capture = json.loads(Path('evox/server-capture.json').read_text())
for asset in server_capture['assets']:
    subprocess.run(['gh', 'release', 'download', server_capture['release_tag'],
                    '--repo', os.environ['GITHUB_REPOSITORY'], '--pattern', asset['name'],
                    '--dir', str(out)], check=True)
    path = out / asset['name']
    h = hashlib.sha256()
    with path.open('rb') as src:
        for block in iter(lambda: src.read(4 * 1024 * 1024), b''):
            h.update(block)
    if path.stat().st_size != asset['bytes'] or h.hexdigest() != asset['sha256']:
        raise SystemExit('Saved server source capture checksum mismatch')
# The new archive has its own aggregate checksum file below.
(out / 'SHA256SUMS').unlink()
record = {
    'commit': commit,
    'run': 'https://github.com/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID'],
    'mesa': lock,
    'server_capture': server_capture,
    'scope': 'Tracked Arch/EvoX porting sources, historical patches, and full upstream Mesa source',
    'full_android_checkout': False,
    'missing': [
        'Unmodified Android upstream repositories are pinned by the saved manifest, not mirrored in full',
        'Complete Arch package source collection and historical cross-toolchain/sysroot inputs',
        'Goodix touch_report and device firmware have no source in this workspace'
    ]
}
(out / 'source-archive.json').write_text(json.dumps(record, indent=2) + '\n')
checksums = []
for path in sorted(out.iterdir()):
    h = hashlib.sha256()
    with path.open('rb') as src:
        for block in iter(lambda: src.read(4 * 1024 * 1024), b''):
            h.update(block)
    checksums.append(h.hexdigest() + '  ' + path.name)
(out / 'SHA256SUMS').write_text('\n'.join(checksums) + '\n')
print('Mesa SHA512 verified:', sha512.hexdigest())
print('Source archives prepared for commit', commit)

"""Resume uploading verified seed assets to an existing draft Release."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import subprocess
import time

from bundle import basename, digest

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('directory', type=Path)
p.add_argument('--repo', default='Dingtaiqi/socrates-Arch')
p.add_argument('--tag', default='verified-seeds-20261110')
p.add_argument('--jobs', type=int, default=4, choices=range(1, 9))
args = p.parse_args()


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


release = next(r for r in api(f'repos/{args.repo}/releases?per_page=100')
               if r['tag_name'] == args.tag)
if not release['draft']:
    raise SystemExit('Seed uploader only writes to a draft Release')
release_id = release['id']
files = {}
manifests = list(args.directory.glob('*.manifest.json'))
if len(manifests) != 2:
    raise SystemExit('Expected exactly two baseline manifests')
pins = json.loads((Path(__file__).parent / 'baselines.json').read_text())
for mpath in manifests:
    m = json.loads(mpath.read_text())
    pin = next(pins[k] for k in ('evox', 'arch') if pins[k]['name'] == m['name'])
    if any(m[k] != pin[k] for k in ('name', 'bytes', 'sha256')):
        raise SystemExit('Manifest differs from pinned baseline')
    for part in m['parts']:
        path = args.directory / basename(part['name'])
        if path.stat().st_size != part['bytes'] or digest(path) != part['sha256']:
            raise SystemExit(f'Invalid local part: {path.name}')
        files[path.name] = (path, part['sha256'])


def upload(item):
    path, expected = item
    for attempt in range(5):
        # Digest comparison makes retries safe even if the last response was lost.
        existing = next((a for a in api(f'repos/{args.repo}/releases/{release_id}/assets?per_page=100')
                         if a['name'] == path.name), None)
        if existing:
            if existing.get('digest') == 'sha256:' + expected and existing['state'] == 'uploaded':
                print(f'VERIFIED {path.name}', flush=True)
                return
            raise RuntimeError(f'Remote asset differs or is incomplete: {path.name}; not overwritten')
        if attempt == 4:
            break
        print(f'UPLOADING {path.name}', flush=True)
        result = subprocess.run(['gh', 'release', 'upload', args.tag, str(path),
                                 '--repo', args.repo], capture_output=True, text=True)
        if result.returncode == 0:
            continue  # Re-query GitHub's stored digest before reporting success.
        print(f'Retry {attempt + 1} for {path.name}: {result.stderr.strip()}', flush=True)
        time.sleep(3)
    raise RuntimeError(f'Upload not verified: {path.name}')


with ThreadPoolExecutor(max_workers=args.jobs) as pool:
    for completed in as_completed([pool.submit(upload, item) for item in files.values()]):
        try:
            completed.result()
        except Exception as error:
            print(f'UPLOAD ERROR: {error}', flush=True)
            raise
# Manifests become visible only after all data parts have been verified.
for path in manifests:
    upload((path, digest(path)))
print('ALL SEED ASSETS VERIFIED ON GITHUB', flush=True)

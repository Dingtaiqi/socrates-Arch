"""Upload the server's bounded source spool directly to GitHub; resumable."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import base64
import fcntl
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

request = json.loads(sys.stdin.readline())
token, repo = request['token'], request['repository']
root = Path('/home/qinghuo/source_exports_20261110/full-source-v1')
lock = (root / 'uploader.lock').open('a')
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
# The proxy passed a small probe but reset TLS during sustained uploads.
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))
started = time.monotonic()
max_seconds = 15000
tag = 'evox-full-source-20261110'
api_root = 'https://api.github.com/repos/' + repo


def api(url, data=None, method=None, extra=None):
    headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28'}
    if extra:
        headers.update(extra)
    for attempt in range(4):
        try:
            if hasattr(data, 'seek'):
                data.seek(0)
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=900) as response:
                return json.load(response) if response.status != 204 else None
        except urllib.error.HTTPError as error:
            if error.code not in (408, 429, 500, 502, 503, 504) or attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))
        except (urllib.error.URLError, OSError):
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))


releases = api(api_root + '/releases?per_page=100')
release = next((r for r in releases if r['tag_name'] == tag), None)
if release is None:
    body = {'tag_name': tag, 'target_commitish': request['commit'], 'draft': True,
            'name': 'Complete offline EvoX source snapshot',
            'body': 'In progress: complete shallow source repositories, LFS inputs, and local porting overlays. '
                    'Generated and uploaded on the build server. ' + request['run_url']}
    release = api(api_root + '/releases', json.dumps(body).encode(),
                  extra={'Content-Type': 'application/json'})
if not release['draft']:
    print('FULL_SOURCE_PUBLISHED ' + json.dumps({'release_tag': tag, 'already_published': True}), flush=True)
    sys.exit(0)
remote = {}
for page in range(1, 30):
    items = api(api_root + f'/releases/{release["id"]}/assets?per_page=100&page={page}')
    remote.update({a['name']: a for a in items})
    if len(items) < 100:
        break


def upload(path, item):
    existing = remote.get(item['name'])
    if existing:
        if existing['state'] == 'uploaded' and existing.get('digest') == 'sha256:' + item['sha256']:
            return existing
        if existing['state'] == 'starter':
            api(api_root + '/releases/assets/' + str(existing['id']), method='DELETE')
        else:
            raise RuntimeError('Refusing mismatched completed asset: ' + item['name'])
    if path.stat().st_size != item['bytes']:
        raise RuntimeError('Spool size differs: ' + item['name'])
    url = release['upload_url'].split('{', 1)[0] + '?name=' + urllib.parse.quote(item['name'])
    try:
        with path.open('rb') as f:
            result = api(url, f, extra={'Content-Type': 'application/octet-stream',
                                       'Content-Length': str(item['bytes'])})
    except urllib.error.HTTPError as error:
        if error.code != 422:
            raise
        # A prior response can be lost after GitHub durably accepted the bytes.
        result = None
        for page in range(1, 30):
            assets = api(api_root + f'/releases/{release["id"]}/assets?per_page=100&page={page}')
            result = next((a for a in assets if a['name'] == item['name']), None)
            if result or len(assets) < 100:
                break
        if not result or result.get('digest') != 'sha256:' + item['sha256']:
            raise
    if result.get('digest') != 'sha256:' + item['sha256']:
        raise RuntimeError('GitHub digest differs: ' + item['name'])
    return result


verified, total = set(), 0
last_report = 0
while True:
    if time.monotonic() - started > max_seconds:
        print('FULL_SOURCE_UPLOAD_PAUSED', len(verified), total, flush=True)
        sys.exit(0)
    failed = root / 'FAILED.json'
    if failed.exists():
        raise RuntimeError('Source producer failed: ' + failed.read_text())
    if (root / 'EXTRA_FAILED.json').exists():
        raise RuntimeError('Extra-input producer failed: ' + (root / 'EXTRA_FAILED.json').read_text())
    pending = []
    for meta in sorted((root / 'parts').glob('*.json')):
        item = json.loads(meta.read_text())
        if item['name'] in verified:
            continue
        path = root / 'parts' / item['name']
        if path.exists() or item['name'] in remote:
            pending.append((path, item))
    if pending:
        pending = pending[:4]
        with ThreadPoolExecutor(max_workers=3) as pool:
            jobs = {pool.submit(upload, p, item): (p, item) for p, item in pending}
            for future in as_completed(jobs):
                path, item = jobs[future]
                result = future.result()
                remote[item['name']] = result
                verified.add(item['name'])
                total += item['bytes']
                # Remove only this generated spool file after durable remote verification.
                assert path.resolve().is_relative_to((root / 'parts').resolve())
                path.unlink(missing_ok=True)
                print('SOURCE_PART_VERIFIED', item['name'], item['bytes'], 'TOTAL', total, flush=True)
    complete = root / 'SNAPSHOT.json'
    if complete.exists() and (root / 'EXTRA_INPUTS.json').exists():
        snapshot = json.loads(complete.read_text())
        snapshot['groups'].append(json.loads((root / 'EXTRA_INPUTS.json').read_text()))
        snapshot['coverage'] += '; includes all audited unmanaged working-tree inputs'
        expected = {p['name'] for g in snapshot['groups'] for p in g['parts']}
        if expected.issubset(verified):
            break
    if time.monotonic() - last_report > 30:
        progress = json.loads((root / 'progress.json').read_text()) if (root / 'progress.json').exists() else {}
        print('SOURCE_UPLOAD_PROGRESS', json.dumps({'verified_parts': len(verified),
                                                   'uploaded_bytes': total, 'producer': progress}), flush=True)
        last_report = time.monotonic()
    time.sleep(5)

snapshot['release_tag'] = tag
snapshot['source_release_url'] = 'https://github.com/' + repo + '/releases/tag/' + tag
# Keep the downloadable index and the Git index byte-identical.
validation = json.loads((root / 'VALIDATION_READY.json').read_text())
if not validation.get('restoration_verified') or not validation.get('configuration_verified'):
    raise RuntimeError('Independent validation has not passed; keeping source release draft')
snapshot['validation'] = validation
data = (json.dumps(snapshot, indent=2) + '\n').encode()
manifest = root / 'SNAPSHOT.public.json'
manifest.write_bytes(data)
item = {'name': 'SNAPSHOT.json', 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
result = upload(manifest, item)
record = {'release_tag': tag, 'release_url': release['html_url'],
          'project_count': snapshot['project_count'], 'groups': len(snapshot['groups']),
          'parts': len(expected), 'compressed_bytes': sum(p['bytes'] for g in snapshot['groups'] for p in g['parts']),
          'manifest_sha256': item['sha256'], 'published': False}
(root / 'UPLOAD_COMPLETE.json').write_text(json.dumps(record, indent=2) + '\n')
print('FULL_SOURCE_UPLOAD_COMPLETE ' + json.dumps(record), flush=True)

content_url = api_root + '/contents/evox/full-source-snapshot.json'
try:
    current = api(content_url + '?ref=main')
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
    current = None
body = {'message': 'Record complete offline build-server source snapshot',
        'content': base64.b64encode(data).decode(), 'branch': 'main'}
if current:
    body['sha'] = current['sha']
committed = api(content_url, json.dumps(body).encode(), method='PUT', extra={'Content-Type': 'application/json'})
record['source_code_commit'] = committed['commit']['sha']
api(api_root + '/releases/' + str(release['id']), json.dumps({
    'draft': False, 'make_latest': 'false',
    'target_commitish': record['source_code_commit'],
    'body': 'Complete committed source repositories, local LFS inputs, seven porting patches and '
            'audited unmanaged build inputs. No build outputs or old Git history. '
            'Restore and build using build.sh in the repository. '
            'Restoration and build-configuration checks passed; a fresh full ROM build is not certified.'
}).encode(), method='PATCH', extra={'Content-Type': 'application/json'})
record['published'] = True
(root / 'UPLOAD_COMPLETE.json').write_text(json.dumps(record, indent=2) + '\n')
print('FULL_SOURCE_PUBLISHED ' + json.dumps(record), flush=True)

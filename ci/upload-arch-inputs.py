"""Publish the allowlisted compiler/sysroot kit directly from the build host."""
import base64
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

request = json.loads(sys.stdin.readline())
base = Path('/home/qinghuo/source_exports_20261110/arch-inputs-v1')
deadline = time.monotonic() + 1800
while not (base / 'INPUTS.json').exists():
    if time.monotonic() > deadline:
        raise SystemExit('Timed out waiting for build input export')
    time.sleep(5)
record = json.loads((base / 'INPUTS.json').read_text())
tag = record['release_tag']
repository = request['repository']
api_root = 'https://api.github.com/repos/' + repository
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))

def api(url, data=None, method=None, content_type='application/json', length=None):
    headers = {'Authorization': 'Bearer ' + request['token'],
               'Accept': 'application/vnd.github+json', 'Content-Type': content_type}
    if length is not None:
        headers['Content-Length'] = str(length)
    req = urllib.request.Request(url, data, headers=headers, method=method)
    for attempt in range(4):
        try:
            if hasattr(data, 'seek'):
                data.seek(0)
            with urllib.request.urlopen(req, timeout=900) as response:
                return json.load(response) if response.status != 204 else None
        except urllib.error.HTTPError:
            raise
        except (OSError, urllib.error.URLError):
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))

releases = api(api_root + '/releases?per_page=100')
release = next((r for r in releases if r['tag_name'] == tag), None)
if not release:
    release = api(api_root + '/releases', json.dumps({'tag_name': tag, 'target_commitish': request['commit'],
        'draft': True, 'name': 'Pinned Arch Turnip build inputs',
        'body': record['coverage'] + '. Generated and uploaded on the original build server.'}).encode())
for item in record['assets']:
    existing = next((a for a in release['assets'] if a['name'] == item['name']), None)
    if existing and existing.get('digest') == 'sha256:' + item['sha256']:
        continue
    if existing:
        if existing['state'] != 'starter':
            raise SystemExit('Conflicting build input asset')
        api(api_root + '/releases/assets/' + str(existing['id']), method='DELETE')
    path = base / item['name']
    with path.open('rb') as source:
        result = api(release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(item['name']),
                     source, content_type='application/octet-stream', length=item['bytes'])
    if result.get('digest') != 'sha256:' + item['sha256']:
        raise SystemExit('Build input upload digest differs')
    print('ARCH_INPUT_UPLOADED', item['name'], item['bytes'], flush=True)
url = api_root + '/contents/arch/build-inputs.json'
try:
    current = api(url + '?ref=main')
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
    current = None
body = {'message': 'Record preserved Arch GPU compiler and sysroot inputs', 'branch': 'main',
        'content': base64.b64encode((json.dumps(record, indent=2) + '\n').encode()).decode()}
if current:
    body['sha'] = current['sha']
api(url, json.dumps(body).encode(), method='PUT')
if release['draft']:
    api(api_root + '/releases/' + str(release['id']), json.dumps({'draft': False, 'make_latest': 'false'}).encode(), method='PATCH')
print('ARCH_BUILD_INPUTS_PUBLISHED', tag, flush=True)

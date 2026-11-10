"""Keep the current compiled partition private, with digest-verified assets."""
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

request = json.loads(sys.stdin.readline())
base = Path(os.environ.get('EVOX_BUILD_PROOF_DIR', '/home/qinghuo/source_exports_20261110/evox-build-proof-v1'))
assets = json.loads((base / 'ASSETS.json').read_text())['assets']
repository = request['repository']
api_root = 'https://api.github.com/repos/' + repository
tag = 'evox-systemimage-proof-20261110'
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))

def api(url, data=None, method=None, length=None):
    headers = {'Authorization': 'Bearer ' + request['token'], 'Accept': 'application/vnd.github+json',
               'Content-Type': 'application/octet-stream' if length is not None else 'application/json'}
    if length is not None:
        headers['Content-Length'] = str(length)
    with urllib.request.urlopen(urllib.request.Request(url, data, headers, method=method), timeout=900) as response:
        return json.load(response) if response.status != 204 else None

releases = api(api_root + '/releases?per_page=100')
release = next((r for r in releases if r['tag_name'] == tag), None)
if not release:
    release = api(api_root + '/releases', json.dumps({'tag_name': tag, 'target_commitish': request['commit'],
        'draft': True, 'name': 'EvoX current source systemimage build proof',
        'body': 'Current original checkout compiled systemimage successfully. Plain system partition build, '
                'not a merged DSU image or historical b66 reproduction. Not device-tested. Kept private. ' + request['run_url']}).encode())
if not release['draft']:
    raise SystemExit('Compiled partition archive must remain draft')
for item in assets:
    existing = next((a for a in release['assets'] if a['name'] == item['name']), None)
    if existing and existing.get('digest') == 'sha256:' + item['sha256']:
        continue
    if existing:
        if existing['state'] != 'starter':
            raise SystemExit('Conflicting completed build proof asset')
        api(api_root + '/releases/assets/' + str(existing['id']), method='DELETE')
    with (base / item['name']).open('rb') as source:
        result = api(release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(item['name']),
                     source, length=item['bytes'])
    if result.get('digest') != 'sha256:' + item['sha256']:
        raise SystemExit('Build proof upload digest differs')
    print('EVOX_BUILD_PROOF_VERIFIED', item['name'], item['bytes'], flush=True)
print('EVOX_BUILD_PROOF_SAVED', tag, flush=True)

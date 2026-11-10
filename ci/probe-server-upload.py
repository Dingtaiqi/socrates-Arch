"""Compare two existing routes using disposable, generated test bytes."""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

r = json.loads(sys.stdin.readline())
base = 'https://api.github.com/repos/' + r['repository']
headers = {'Authorization': 'Bearer ' + r['token'], 'Accept': 'application/vnd.github+json'}

def api(url, data=None, method=None):
    req = urllib.request.Request(url, data, headers={**headers, 'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response) if response.status != 204 else None

release = api(base + '/releases', json.dumps({'tag_name': 'network-probe-' + r['run_id'],
              'target_commitish': r['commit'], 'name': 'Temporary generated network probe', 'draft': True}).encode())
try:
    payload = os.urandom(8 * 1024 * 1024)
    for proxy in [r['relay_proxy']] if r.get('relay_proxy') else [None, 'http://127.0.0.1:7890']:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler(
            {'http': proxy, 'https': proxy} if proxy else {}))
        name = 'relay.bin' if r.get('relay_proxy') else ('proxy.bin' if proxy else 'direct.bin')
        url = release['upload_url'].split('{')[0] + '?name=' + name
        req = urllib.request.Request(url, payload, headers={**headers, 'Content-Type': 'application/octet-stream'})
        start = time.monotonic()
        try:
            with opener.open(req, timeout=120) as response:
                result = json.load(response)
            assert result.get('digest') == 'sha256:' + hashlib.sha256(payload).hexdigest()
            print('NETWORK_PROBE', name, 'bytes', len(payload), 'seconds', round(time.monotonic()-start, 3), flush=True)
            api(base + '/releases/assets/' + str(result['id']), method='DELETE')
        except Exception as error:
            print('NETWORK_PROBE_ERROR', name, type(error).__name__, flush=True)
finally:
    api(base + '/releases/' + str(release['id']), method='DELETE')

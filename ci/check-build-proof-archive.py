"""Check the saved proof before requesting any connection to the old host."""
import json
import os
from pathlib import Path
import urllib.request

root = Path(__file__).resolve().parents[1]
expected = json.loads((root / 'evox/build-proof-assets.json').read_text())
request = urllib.request.Request('https://api.github.com/repos/' +
    os.environ['GITHUB_REPOSITORY'] + '/releases?per_page=100',
    headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
             'Accept': 'application/vnd.github+json'})
with urllib.request.urlopen(request, timeout=60) as response:
    releases = json.load(response)
release = next((r for r in releases if r['tag_name'] == expected['release_tag']), {})
assets = {item['name']: item for item in release.get('assets', [])}
complete = release.get('draft') is expected['draft'] and all(
    assets.get(item['name'], {}).get('state') == 'uploaded' and
    assets[item['name']]['size'] == item['bytes'] and
    assets[item['name']].get('digest') == 'sha256:' + item['sha256']
    for item in expected['assets'])
with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
    output.write('archived=' + str(complete).lower() + '\n')
print('BUILD_PROOF_ALREADY_ARCHIVED' if complete else 'BUILD_PROOF_NEEDS_UPLOAD', flush=True)

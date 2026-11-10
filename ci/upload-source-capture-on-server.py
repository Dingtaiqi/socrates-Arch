"""Sanitize and upload a completed capture directly from the build server.

The short-lived, repository-scoped GitHub token arrives on SSH stdin. It is
never written into the export or a credentials file.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tarfile
import time
import urllib.parse
import urllib.request

request = json.loads(sys.stdin.readline())
token, repository = request['token'], request['repository']
base = Path('/home/qinghuo/source_exports_20261110')
deadline = time.monotonic() + 3600
while not (base / 'CAPTURE_READY.json').is_file():
    if time.monotonic() > deadline:
        raise SystemExit('Timed out waiting for the source capture')
    time.sleep(10)
capture = base / 'capture-v1'
ready = json.loads((base / 'CAPTURE_READY.json').read_text())
summary = ready['summary']
if summary['manifest_rc'] or summary['git_failures'] or summary['errors']:
    raise SystemExit('Source capture contains unresolved errors')
publish = base / ('publish-' + request['run_id'])
publish.mkdir(mode=0o700, exist_ok=False)
secrets = {token}
credential_helper = Path('/home/qinghuo/srv_build_base66.sh').read_text()
match = re.search(r'''(?m)^P=['"]([^'"\r\n]+)['"]''', credential_helper)
if not match:
    raise SystemExit('Existing credential helper could not be checked')
secrets.add(match[1])
texts = {}
for path in capture.rglob('*'):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    texts[path] = text
    # Existing server helper credentials and optional personal Wi-Fi settings.
    pattern = r'''(?mi)^\s*(?:export\s+)?(?:PASS|PASSWORD|SUDO_PASS(?:WORD)?|WIFI_PASS|WIFI_SSID|WIFI_SCAN_FILTER|GH_TOKEN|GITHUB_TOKEN|API_KEY)\s*=\s*(['"])([^'"\r\n]+)\1'''
    for match in re.finditer(pattern, text):
        value = match[2]
        if len(value) >= 4 and not value.startswith(('/', '$', 'REDACTED')):
            secrets.add(value)
    if path.parent.name == 'server-scripts':
        for match in re.finditer(r'''(?i)(?:password|passwd|sudo_pass|api_key)\s*=\s*(['"])([^'"\r\n]+)\1''', text):
            if len(match[2]) >= 4 and '$' not in match[2]:
                secrets.add(match[2])
redactions, excluded = [], []
private_key = re.compile(r'(?m)^-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----')
github_token = re.compile(r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}')
for path in sorted(capture.rglob('*')):
    if not path.is_file():
        continue
    rel = path.relative_to(capture)
    output = publish / rel
    output.parent.mkdir(parents=True, exist_ok=True)
    text = texts.get(path)
    if text is None:
        data = path.read_bytes()
        if any(secret.encode() in data for secret in secrets):
            excluded.append(str(rel))
            continue
        shutil.copyfile(path, output)
        continue
    if private_key.search(text):
        excluded.append(str(rel))
        continue
    original = text
    for secret in sorted(secrets, key=len, reverse=True):
        text = text.replace(secret, 'REDACTED_PRIVATE_VALUE')
    text = github_token.sub('REDACTED_GITHUB_TOKEN', text)
    text = re.sub(r'https?://[^\s/:]+:[^\s/@]+@', 'https://', text)
    output.write_text(text, encoding='utf-8')
    if text != original:
        redactions.append(str(rel))

# Keep the per-file identities accurate after credential removal.
for metadata in [publish / 'projects.json', *publish.glob('projects/*/project.json')]:
    obj = json.loads(metadata.read_text())
    entries = obj if isinstance(obj, list) else [obj]
    for project in entries:
        for file in project.get('files', []):
            path = publish / 'projects' / project['id'] / 'files' / file['path']
            if path.is_file():
                file['bytes'] = path.stat().st_size
                file['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                file.pop('sha256', None)
                file['excluded_sensitive'] = True
        if project.get('files') or project.get('patch_bytes'):
            # Preserve upstream license/notice files for the copied sources.
            original_project = Path('/build/evox') / project['path']
            for name in ('LICENSE', 'NOTICE', 'COPYING', 'LICENSE.txt'):
                path = original_project / name
                if path.is_file() and path.stat().st_size < 4 * 1024 * 1024:
                    target = publish / 'projects' / project['id'] / 'licenses' / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, target)
    metadata.write_text(json.dumps(obj, indent=2) + '\n')

record = {
    'summary': summary,
    'source_checkout': 'EvoX current checkout, 2026-11-10',
    'coverage': 'Resolved revisions for all projects; tracked patches, selected untracked source files, server recipes and Arch package metadata',
    'unmodified_upstream_projects': 'Referenced by fixed commit IDs, not duplicated as a complete Android tree',
    'redacted_files': redactions,
    'excluded_sensitive_files': excluded,
    'run_url': request['run_url'],
}
(publish / 'ARCHIVE_RECORD.json').write_text(json.dumps(record, indent=2) + '\n')
for path in publish.rglob('*'):
    if path.is_file():
        try:
            content = path.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            continue
        if private_key.search(content) or github_token.search(content):
            raise SystemExit('Sensitive material remains in ' + str(path.relative_to(publish)))

assets = base / ('assets-' + request['run_id'])
assets.mkdir(mode=0o700, exist_ok=False)
archive = assets / 'evox-arch-server-sources-20261110.tar.gz'
with tarfile.open(archive, 'w:gz', compresslevel=1) as tar:
    tar.add(publish, arcname='server-sources')
shutil.copyfile(publish / 'manifest.lock.xml', assets / 'evox-manifest.lock.xml')
shutil.copyfile(publish / 'ARCHIVE_RECORD.json', assets / 'ARCHIVE_RECORD.json')
checksums = []
for path in sorted(assets.iterdir()):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
            h.update(block)
    checksums.append(h.hexdigest() + '  ' + path.name)
(assets / 'SHA256SUMS').write_text('\n'.join(checksums) + '\n')

def api(url, data=None, extra=None):
    headers = {'Authorization': 'Bearer ' + token,
               'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28'}
    if extra:
        headers.update(extra)
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=300) as response:
        return json.load(response)

tag = 'build-server-sources-' + request['run_id']
body = {'tag_name': tag, 'target_commitish': request['commit'], 'draft': True,
        'name': 'EvoX + Arch build-server source capture',
        'body': 'Exported, sanitized, hashed and uploaded directly on the build server. '
                'Includes fixed revisions, local changes, server recipes and Arch package metadata. '
                'Unmodified upstream repositories are referenced by commit ID. ' + request['run_url']}
release = api('https://api.github.com/repos/' + repository + '/releases',
              json.dumps(body).encode(), {'Content-Type': 'application/json'})
uploaded = []
for path in sorted(assets.iterdir()):
    if path.stat().st_size >= 2 * 1024 ** 3:
        raise SystemExit('Asset requires splitting before upload')
    url = release['upload_url'].split('{', 1)[0] + '?name=' + urllib.parse.quote(path.name)
    with path.open('rb') as source:
        result = api(url, source, {'Content-Type': 'application/octet-stream',
                                  'Content-Length': str(path.stat().st_size)})
    expected = hashlib.sha256(path.read_bytes()).hexdigest()
    if result.get('digest') != 'sha256:' + expected:
        raise SystemExit('Uploaded asset digest mismatch: ' + path.name)
    uploaded.append({'name': path.name, 'bytes': path.stat().st_size, 'sha256': expected})
    print('SERVER_UPLOADED_VERIFIED', path.name, path.stat().st_size, flush=True)
result = {'release_tag': tag, 'release_url': release['html_url'], 'summary': summary,
          'redacted_files': len(redactions), 'excluded_sensitive_files': excluded,
          'assets': uploaded}
(base / 'UPLOAD_COMPLETE.json').write_text(json.dumps(result, indent=2) + '\n')
print('DIRECT_SERVER_UPLOAD_COMPLETE ' + json.dumps(result), flush=True)

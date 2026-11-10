"""Copy only the prepared proof to the cloud runner, then verify and archive it."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.request

import paramiko

remote = '''from pathlib import Path
import json, shutil, sys
base = Path('/home/qinghuo/source_exports_20261110/evox-build-proof-v1')
assets = json.loads((base / 'ASSETS.json').read_text())
sys.stdout.buffer.write((json.dumps(assets) + '\\n').encode())
sys.stdout.buffer.flush()
requested = set(json.loads(sys.stdin.readline()))
assert requested.issubset({item['name'] for item in assets['assets']})
for item in assets['assets']:
    if item['name'] not in requested:
        continue
    assert Path(item['name']).name == item['name']
    with (base / item['name']).open('rb') as source:
        shutil.copyfileobj(source, sys.stdout.buffer, 1024 * 1024)
    sys.stdout.buffer.flush()
'''
client = paramiko.SSHClient()
for line in os.environ['BUILD_KNOWN_HOSTS'].splitlines():
    entry = paramiko.hostkeys.HostKeyEntry.from_line(line)
    if entry:
        for name in entry.hostnames:
            client.get_host_keys().add(name, entry.key.get_name(), entry.key)
client.set_missing_host_key_policy(paramiko.RejectPolicy())
try:
    client.connect(os.environ['BUILD_HOST'], port=int(os.environ['BUILD_PORT']),
                   username=os.environ['BUILD_USER'], password=os.environ['BUILD_PASSWORD'],
                   allow_agent=False, look_for_keys=False, timeout=15,
                   banner_timeout=30, auth_timeout=30)
    client.get_transport().set_keepalive(20)
    stdin, stdout, stderr = client.exec_command('python3 -u -c ' + shlex.quote(remote), timeout=180)
    stdout.channel.settimeout(180)
    with tempfile.TemporaryDirectory(prefix='evox-build-proof-') as directory:
        base = Path(directory)
        manifest = json.loads(stdout.readline())
        (base / 'ASSETS.json').write_text(json.dumps(manifest))
        request = urllib.request.Request('https://api.github.com/repos/' +
            os.environ['GITHUB_REPOSITORY'] + '/releases?per_page=100',
            headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                     'Accept': 'application/vnd.github+json'})
        with urllib.request.urlopen(request, timeout=60) as response:
            releases = json.load(response)
        release = next((r for r in releases if r['tag_name'] == 'evox-systemimage-proof-20261110'), {})
        existing = {item['name']: item for item in release.get('assets', [])}
        requested = {item['name'] for item in manifest['assets']
                     if existing.get(item['name'], {}).get('digest') != 'sha256:' + item['sha256']}
        stdin.write(json.dumps(sorted(requested)) + '\n')
        stdin.flush()
        for item in manifest['assets']:
            if item['name'] not in requested:
                print('PROOF_ALREADY_ARCHIVED', item['name'], flush=True)
                continue
            if Path(item['name']).name != item['name']:
                raise ValueError('Unexpected build proof path')
            started, received = time.monotonic(), 0
            digest = hashlib.sha256()
            with (base / item['name']).open('xb') as output:
                while received < item['bytes']:
                    block = stdout.read(min(1024 * 1024, item['bytes'] - received))
                    if not block:
                        raise OSError('Incomplete proof relay')
                    output.write(block)
                    digest.update(block)
                    received += len(block)
                    if received % (64 * 1024 * 1024) == 0:
                        print('PROOF_RELAY_PROGRESS', received, item['bytes'], flush=True)
            if digest.hexdigest() != item['sha256']:
                raise ValueError('Relayed proof checksum differs')
            print('PROOF_RELAY_VERIFIED', item['name'], received,
                  'seconds', round(time.monotonic() - started, 2), flush=True)
        if stdout.read(1) or stdout.channel.recv_exit_status():
            raise OSError('Proof relay stream did not finish cleanly')
        request = {'token': os.environ['GH_TOKEN'], 'repository': os.environ['GITHUB_REPOSITORY'],
                   'commit': os.environ['GITHUB_SHA'], 'run_url': 'https://github.com/' +
                   os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID']}
        subprocess.run([sys.executable, str(Path(__file__).with_name('upload-evox-build-proof.py'))],
                       input=json.dumps(request).encode(), check=True,
                       env={**os.environ, 'EVOX_BUILD_PROOF_DIR': str(base)})
finally:
    client.close()

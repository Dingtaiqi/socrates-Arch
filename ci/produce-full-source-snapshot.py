"""Produce offline shallow Git snapshots on the build server, with bounded spool.

All committed source, required Git LFS objects and the captured local overlays
are retained. Build outputs and old Git history are not part of this snapshot.
"""
import concurrent.futures
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import time
import xml.etree.ElementTree as ET
import urllib.parse

BASE = Path('/home/qinghuo/source_exports_20261110')
ROOT = Path('/build/evox')
OUT = BASE / 'full-source-v1'
PART_BYTES = 512 * 1024 * 1024
for p in [OUT, OUT / 'parts', OUT / 'groups', OUT / 'staging']:
    p.mkdir(mode=0o700, exist_ok=True)
    os.chown(p, 1000, 1000)
ENV = {**os.environ, 'GIT_OPTIONAL_LOCKS': '0', 'GIT_LFS_SKIP_SMUDGE': '1',
       'GIT_ATTR_NOSYSTEM': '1',
       'GIT_CONFIG_COUNT': '3', 'GIT_CONFIG_KEY_0': 'safe.directory',
       'GIT_CONFIG_VALUE_0': '*', 'GIT_CONFIG_KEY_1': 'pack.threads',
       'GIT_CONFIG_VALUE_1': '4', 'GIT_CONFIG_KEY_2': 'core.fsmonitor',
       'GIT_CONFIG_VALUE_2': 'false'}
state = {'projects_done': 0, 'groups_done': 0, 'stage': 'initializing'}


def save(path, data):
    temp = path.with_name(path.name + '.writing')
    temp.write_text(json.dumps(data, indent=2) + '\n')
    os.chmod(temp, 0o600)
    os.chown(temp, 1000, 1000)
    temp.replace(path)


def progress(**fields):
    state.update(fields, updated=time.time())
    save(OUT / 'progress.json', state)


def run(args, cwd=None):
    p = subprocess.run(args, cwd=cwd, env=ENV, capture_output=True, timeout=7200)
    if p.returncode:
        raise RuntimeError(str(args[:3]) + ': ' + p.stderr.decode(errors='replace')[-1500:])
    return p.stdout


def file_hash(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


class Parts:
    def __init__(self, prefix):
        self.prefix, self.file, self.entries = prefix, None, []
        self.total, self.digest = 0, hashlib.sha256()

    def write(self, data):
        length = len(data)
        self.digest.update(data)
        self.total += length
        while data:
            if self.file is None:
                # The uploader removes a part only after GitHub verifies its hash.
                while sum(p.stat().st_size for p in (OUT / 'parts').glob('*.part*')
                          if not p.name.endswith(('.json', '.partial'))) >= 2 * 1024 ** 3:
                    progress(stage='waiting_for_upload_spool')
                    time.sleep(5)
                self.name = self.prefix + f'.part{len(self.entries):04d}'
                self.path = OUT / 'parts' / (self.name + '.partial')
                self.file = self.path.open('xb')
                self.size, self.hash = 0, hashlib.sha256()
            block = data[:PART_BYTES - self.size]
            self.file.write(block)
            self.hash.update(block)
            self.size += len(block)
            data = data[len(block):]
            if self.size == PART_BYTES:
                self.close()
        return length

    def flush(self):
        if self.file:
            self.file.flush()

    def close(self):
        if self.file:
            self.file.flush()
            os.fsync(self.file.fileno())
            self.file.close()
            self.file = None
            target = OUT / 'parts' / self.name
            self.path.rename(target)
            os.chown(target, 1000, 1000)
            os.chmod(target, 0o600)
            item = {'name': self.name, 'bytes': self.size, 'sha256': self.hash.hexdigest()}
            self.entries.append(item)
            save(target.with_name(target.name + '.json'), item)


def mirror(project):
    src = ROOT / project['path']
    directory = OUT / 'staging' / (project['id'] + '.git')
    if directory.exists():
        assert directory.resolve().is_relative_to((OUT / 'staging').resolve())
        shutil.rmtree(directory)
    progress(stage='cloning', current_project=project['path'])
    run(['git', 'clone', '--quiet', '--bare', '--no-local', '--depth', '1',
         'file://' + str(src), str(directory)])
    git = ['git', '--git-dir=' + str(directory)]
    head = run(git + ['rev-parse', 'HEAD']).decode().strip()
    if head != project['head']:
        raise RuntimeError('Project HEAD changed: ' + project['path'])
    run(git + ['fsck', '--connectivity-only', '--no-reflogs', '--no-dangling'])
    # Use the original checkout only to locate locally available LFS objects.
    lfs = run(['git', '-C', str(src), 'lfs', 'ls-files', '--long', 'HEAD']).decode()
    objects = []
    if lfs.strip():
        # ls-files also finds literal pointer text used by source-code tests.
        # Only committed filter=lfs paths require external object payloads.
        run(git + ['read-tree', 'HEAD'])
        required = []
        try:
            for line in lfs.splitlines():
                name = line[67:]
                attrs = run(git + ['-c', 'core.attributesFile=/dev/null', 'check-attr',
                                   '--cached', '-z', 'filter', '--', name])
                if attrs.split(b'\0')[2] == b'lfs':
                    required.append(line)
                else:
                    print('LITERAL_LFS_POINTER_RETAINED', project['path'], name, flush=True)
        finally:
            (directory / 'index').unlink(missing_ok=True)
        envtext = run(['git', '-C', str(src), 'lfs', 'env']).decode()
        media = Path(next(l.split('=', 1)[1] for l in envtext.splitlines()
                          if l.startswith('LocalMediaDir=')))
        missing = []
        for line in required:
            m = re.match(r'^([0-9a-f]{64})\s+[-*]\s+(.+)$', line)
            if not m:
                raise RuntimeError('Unrecognized LFS listing in ' + project['path'])
            oid, name = m.groups()
            objects.append({'oid': oid, 'path': name})
            target = directory / 'lfs/objects' / oid[:2] / oid[2:4] / oid
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                continue
            candidates = [media / oid[:2] / oid[2:4] / oid, src / name]
            origin = next((p for p in candidates if p.is_file() and file_hash(p) == oid), None)
            if origin:
                os.link(origin, target)
            else:
                missing.append(oid)
        if missing:
            run(git + ['remote', 'set-url', 'origin', project['url']])
            run(git + ['lfs', 'fetch', '--include=' + ','.join(o['path'] for o in objects),
                       '--exclude=', 'origin', project['head']])
        for obj in objects:
            p = directory / 'lfs/objects' / obj['oid'][:2] / obj['oid'][2:4] / obj['oid']
            if not p.is_file() or file_hash(p) != obj['oid']:
                raise RuntimeError('Missing/corrupt required LFS object: ' + project['path'])
    run(git + ['remote', 'set-url', 'origin', project['url']])
    return directory, {**project, 'lfs_objects': len(objects)}


def main():
    (OUT / 'FAILED.json').unlink(missing_ok=True)
    xml = ET.parse(BASE / 'capture-v1/manifest.lock.xml')
    remotes = {e.get('name'): e.get('fetch') for e in xml.findall('remote')}
    default_remote = xml.find('default').get('remote')
    records = {r['path']: r for r in json.loads((BASE / 'capture-v1/projects.json').read_text())}
    projects = []
    manifest_url = run(['git', '-C', str(ROOT / '.repo/manifests'), 'config',
                        '--get', 'remote.origin.url']).decode().strip()
    for e in xml.findall('project'):
        path = e.get('path', e.get('name'))
        fetch = remotes[e.get('remote', default_remote)]
        fetch = urllib.parse.urljoin(manifest_url, fetch)
        if not fetch.startswith(('https://', 'http://', 'git://', 'ssh://')):
            raise RuntimeError('Unsupported relative manifest remote: ' + fetch)
        project = {'path': path, 'id': hashlib.sha256(path.encode()).hexdigest()[:20],
                   'head': e.get('revision'), 'url': fetch.rstrip('/') + '/' + e.get('name'),
                   'kind': 'project'}
        projects.append(project)
    for path, kind, url in [('.repo/repo', 'repo_tool', 'https://gerrit.googlesource.com/git-repo'),
                            ('.repo/manifests', 'manifests', 'https://github.com/Evolution-X/manifest')]:
        head = run(['git', '-C', str(ROOT / path), 'rev-parse', 'HEAD']).decode().strip()
        projects.append({'path': path, 'id': hashlib.sha256(path.encode()).hexdigest()[:20],
                         'head': head, 'url': url, 'kind': kind})
    projects.sort(key=lambda p: (0 if records.get(p['path'], {}).get('patch_bytes') else
                                1 if p['path'].startswith(('device/', 'kernel/', 'hardware/')) else
                                2 if p['path'].startswith('prebuilts/') else 3, p['path']))
    all_groups, done = [], 0
    for number, offset in enumerate(range(0, len(projects), 8)):
        completed = OUT / 'groups' / f'g{number:04d}.json'
        if completed.exists():
            group = json.loads(completed.read_text())
            all_groups.append(group)
            done += len(group['projects'])
            continue
        attempts = list((OUT / 'parts').glob(f'source-g{number:04d}-a*'))
        attempt = 1 + max([int(re.search(r'-a(\d+)', p.name)[1]) for p in attempts] or [0])
        prefix = f'source-g{number:04d}-a{attempt:02d}.tar.gz'
        parts = Parts(prefix)
        entries = []
        try:
            with gzip.GzipFile(filename='', mode='wb', fileobj=parts, compresslevel=1, mtime=0) as gz:
                with tarfile.open(fileobj=gz, mode='w|') as tar:
                    for project in projects[offset:offset + 8]:
                        directory, item = mirror(project)
                        tar.add(directory, arcname='mirrors/' + project['id'] + '.git')
                        entries.append(item)
                        assert directory.resolve().is_relative_to((OUT / 'staging').resolve())
                        shutil.rmtree(directory)
                        done += 1
                        progress(stage='archiving', projects_done=done, total_projects=len(projects))
                    if number == 0:
                        tar.add(BASE / 'assets-42747624122/evox-arch-server-sources-20261110.tar.gz',
                                arcname='meta/porting-overlay.tar.gz')
                        tar.add(BASE / 'capture-v1/manifest.lock.xml', arcname='meta/manifest.lock.xml')
                        for name in ['lk_inc.mk', 'm']:
                            if (ROOT / name).is_file():
                                tar.add(ROOT / name, arcname='root-files/' + name)
        finally:
            parts.close()
        group = {'index': number, 'compression': 'gzip', 'bytes': parts.total,
                 'sha256': parts.digest.hexdigest(), 'parts': parts.entries, 'projects': entries}
        save(completed, group)
        all_groups.append(group)
        progress(stage='group_complete', groups_done=len(all_groups), projects_done=done)
        print('GROUP_COMPLETE', number, 'PROJECTS', done, 'BYTES', parts.total, flush=True)
    manifest = {'schema': 1, 'date': '2026-11-10', 'device': 'socrates',
                'project_count': 1265, 'groups': all_groups,
                'coverage': 'Complete committed source and current LFS inputs, shallow Git data, and local porting overlays; excludes build outputs and old Git history'}
    save(OUT / 'SNAPSHOT.json', manifest)
    progress(stage='complete', projects_done=done, groups_done=len(all_groups))
    print('FULL_SOURCE_SNAPSHOT_COMPLETE', done, flush=True)


try:
    main()
except Exception as error:
    save(OUT / 'FAILED.json', {'error': type(error).__name__ + ': ' + str(error), 'state': state})
    raise

#!/usr/bin/env python3
"""Restore the pinned, shallow Android source snapshot without repo sync."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ENV = {**os.environ, 'GIT_LFS_SKIP_SMUDGE': '1', 'GIT_OPTIONAL_LOCKS': '0', 'GIT_ATTR_NOSYSTEM': '1'}


def run(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, env=ENV, stderr=subprocess.PIPE)


def safe_path(root, name):
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts or '\\' in name:
        raise ValueError('Unsafe archive or manifest path: ' + name)
    path = root.joinpath(*rel.parts)
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Path escapes destination: ' + name)
    return path


class JoinedParts(io.RawIOBase):
    def __init__(self, paths):
        self.paths = iter(paths)
        self.current = None

    def readable(self):
        return True

    def read(self, size=-1):
        if size < 0:
            raise ValueError('Streaming archive requires bounded reads')
        data = bytearray()
        while len(data) < size:
            if self.current is None:
                try:
                    self.current = next(self.paths).open('rb')
                except StopIteration:
                    break
            block = self.current.read(size - len(data))
            if block:
                data.extend(block)
            else:
                self.current.close()
                self.current = None
        return bytes(data)

    def close(self):
        if self.current:
            self.current.close()
        super().close()


def extract(stream, destination):
    """Handle regular files and internal links; never honor archive ownership."""
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=stream, mode='r|gz') as archive:
        for member in archive:
            target = safe_path(destination, member.name)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() or target.is_symlink():
                raise ValueError('Duplicate archive path: ' + member.name)
            if member.isreg():
                with archive.extractfile(member) as source, target.open('xb') as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                target.chmod(member.mode & 0o777)
            elif member.islnk():
                source = safe_path(destination, member.linkname)
                if not source.is_file() or source.is_symlink():
                    raise ValueError('Invalid archive hardlink')
                os.link(source, target)
            elif member.issym():
                link = PurePosixPath(member.linkname)
                if link.is_absolute() or not (target.parent / str(link)).resolve().is_relative_to(destination.resolve()):
                    raise ValueError('Archive symlink escapes destination')
                target.symlink_to(member.linkname)
            else:
                raise ValueError('Unsupported archive member: ' + member.name)


def verify_parts(paths, group):
    whole = hashlib.sha256()
    for path, item in zip(paths, group['parts']):
        digest, size = hashlib.sha256(), 0
        with path.open('rb') as source:
            for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
                digest.update(block)
                whole.update(block)
                size += len(block)
        if size != item['bytes'] or digest.hexdigest() != item['sha256']:
            raise ValueError('Source part checksum differs: ' + item['name'])
    if whole.hexdigest() != group['sha256']:
        raise ValueError('Source group checksum differs')


def download(url, target, item):
    if target.exists():
        return
    temporary = target.with_name(target.name + '.download')
    for attempt in range(6):
        start = temporary.stat().st_size if temporary.exists() else 0
        request = urllib.request.Request(url, headers={'Range': f'bytes={start}-'} if start else {})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                append = start and response.status == 206
                if append and not response.headers.get('Content-Range', '').startswith(f'bytes {start}-'):
                    raise ValueError('Unexpected download range')
                with temporary.open('ab' if append else 'wb') as output:
                    shutil.copyfileobj(response, output, 1024 * 1024)
            if temporary.stat().st_size != item['bytes']:
                raise OSError('Incomplete source part')
            temporary.replace(target)
            return
        except (OSError, urllib.error.URLError):
            if attempt == 5:
                raise
            time.sleep(min(5 * (attempt + 1), 30))


def install_repository(project, scratch, root):
    path, kind = project['path'], project.get('kind', 'project')
    worktree = safe_path(root, path)
    git_relative = ('.repo/manifests.git' if kind == 'manifests' else
                    '.repo/repo.git' if kind == 'repo_tool' else '.repo/projects/' + path + '.git')
    gitdir = safe_path(root, git_relative)
    receipt = root / '.source-restore' / ('repo-' + project['id'] + '.json')
    if receipt.exists():
        if json.loads(receipt.read_text()) != project:
            raise ValueError('Restored repository metadata differs: ' + path)
        return
    # A failed checkout may be resumed, but never adopt an unrelated existing tree.
    pending = receipt.with_suffix('.pending')
    if not pending.exists():
        if gitdir.exists() or (worktree.exists() and any(worktree.iterdir())):
            raise ValueError('Refusing existing source path: ' + path)
        pending.write_text(json.dumps(project))
    elif json.loads(pending.read_text()) != project:
        raise ValueError('Pending repository differs: ' + path)
    if not gitdir.exists():
        gitdir.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(scratch / 'mirrors' / (project['id'] + '.git')), gitdir)
    if (gitdir / 'objects/info/alternates').exists():
        raise ValueError('Snapshot unexpectedly depends on external Git objects')
    worktree.mkdir(parents=True, exist_ok=True)
    git = ['git', '--git-dir=' + str(gitdir), '--work-tree=' + str(worktree)]
    run(git + ['config', 'core.bare', 'false'])
    run(git + ['config', 'core.worktree', os.path.relpath(worktree, gitdir)])
    link = worktree / '.git'
    if not link.is_symlink():
        if link.exists():
            raise ValueError('Existing .git is not a restore-owned symlink')
        link.symlink_to(os.path.relpath(gitdir, worktree), target_is_directory=True)
    if run(git + ['rev-parse', 'HEAD']).decode().strip() != project['head']:
        raise ValueError('Snapshot HEAD differs: ' + path)
    run(git + ['fsck', '--connectivity-only', '--no-reflogs', '--no-dangling'])
    if project.get('lfs_objects'):
        # Keep filters and the bundled object store local to the restored repo.
        run(git + ['config', 'lfs.storage', 'lfs'])
        run(['git', 'lfs', 'install', '--local', '--force', '--skip-smudge', '--skip-repo'], cwd=worktree)
    run(git + ['reset', '--hard', project['head']], cwd=worktree)
    if project.get('lfs_objects'):
        listing = run(['git', 'lfs', 'ls-files', '--long', 'HEAD'], cwd=worktree).decode()
        required = []
        for line in listing.splitlines():
            name = line[67:]
            attrs = run(git + ['-c', 'core.attributesFile=/dev/null', 'check-attr',
                               '--cached', '-z', 'filter', '--', name])
            if attrs.split(b'\0')[2] == b'lfs':
                required.append((line[:64], name))
        if len(required) != project['lfs_objects']:
            raise ValueError('Required LFS file count differs: ' + path)
        run(['git', 'lfs', 'checkout', '--'] + [name for oid, name in required], cwd=worktree)
        # Check the payloads themselves, leaving literal pointer test fixtures
        # without filter=lfs untouched and independent of nonexistent objects.
        for oid, name in required:
            digest = hashlib.sha256()
            with safe_path(worktree, name).open('rb') as source:
                for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
                    digest.update(block)
            if digest.hexdigest() != oid:
                raise ValueError('LFS payload checksum differs: ' + path + '/' + name)
    receipt.write_text(json.dumps(project))
    pending.unlink()
    print('RESTORED', path, project['head'], flush=True)


def copy_tree_files(source, root):
    if not source.exists():
        return
    for directory, dirs, files in os.walk(source, followlinks=False):
        # Preserve symlink directories as links rather than traversing them.
        for name in dirs[:]:
            if (Path(directory) / name).is_symlink():
                dirs.remove(name)
                files.append(name)
        for name in files:
            path = Path(directory) / name
            target = safe_path(root, path.relative_to(source).as_posix())
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.is_symlink():
                if target.is_symlink() and os.readlink(target) == os.readlink(path):
                    continue
                if target.exists() or target.is_symlink():
                    raise ValueError('Existing extra-input symlink target: ' + str(target))
                link = os.readlink(path)
                if Path(link).is_absolute() or not (target.parent / link).resolve().is_relative_to(root):
                    raise ValueError('Extra-input link escapes source tree')
                target.symlink_to(link)
            else:
                if target.is_symlink():
                    raise ValueError('Extra input would follow a symlink')
                if target.is_file() and target.stat().st_size == path.stat().st_size:
                    with path.open('rb') as a, target.open('rb') as b:
                        if all(x == b.read(len(x)) for x in iter(lambda: a.read(1024 * 1024), b'')):
                            continue
                shutil.copy2(path, target)


def apply_overlay(root, selected):
    state = root / '.source-restore'
    archive = state / 'meta/porting-overlay.tar.gz'
    if not archive.exists():
        raise ValueError('Missing group zero with local porting overlay')
    overlay = state / 'overlay'
    if not overlay.exists():
        with tempfile.TemporaryDirectory(dir=state) as temp:
            with archive.open('rb') as stream:
                extract(stream, Path(temp))
            shutil.move(str(Path(temp) / 'server-sources'), overlay)
    for project in json.loads((overlay / 'projects.json').read_text()):
        if project['path'] not in selected:
            continue
        receipt = state / ('overlay-' + project['id'])
        if receipt.exists():
            continue
        source = overlay / 'projects' / project['id']
        worktree = safe_path(root, project['path'])
        patch = source / 'tracked.patch'
        if patch.exists():
            try:
                run(['git', 'apply', '--check', str(patch)], cwd=worktree)
            except subprocess.CalledProcessError:
                run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=worktree)
            else:
                run(['git', 'apply', str(patch)], cwd=worktree)
        for record in project.get('files', []):
            if record.get('excluded_sensitive'):
                raise ValueError('Required local input was excluded: ' + record['path'])
            path = safe_path(source / 'files', record['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
                raise ValueError('Local overlay checksum differs')
            target = safe_path(worktree, record['path'])
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        receipt.touch()


def setup_manifest(root, selected):
    source = root / '.source-restore/meta/manifest.lock.xml'
    tree = ET.parse(source)
    for project in tree.findall('project'):
        name = project.get('path', project.get('name'))
        if name not in selected:
            continue
        project_root = safe_path(root, name)
        # repo's Project.Exists checks both gitdir and objdir, even when each
        # restored gitdir already owns its complete object database.
        objects = safe_path(root, '.repo/project-objects/' + project.get('name') + '.git')
        if not objects.exists():
            objects.parent.mkdir(parents=True, exist_ok=True)
            gitdir = safe_path(root, '.repo/projects/' + name + '.git')
            objects.symlink_to(os.path.relpath(gitdir, objects.parent), target_is_directory=True)
        for entry in list(project):
            if entry.tag not in ('copyfile', 'linkfile'):
                continue
            origin = safe_path(project_root, entry.get('src'))
            target = safe_path(root, entry.get('dest'))
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_file() or target.is_symlink():
                target.unlink()
            if entry.tag == 'copyfile':
                shutil.copy2(origin, target)
            else:
                target.symlink_to(os.path.relpath(origin, target.parent), target_is_directory=origin.is_dir())
    manifests = root / '.repo/manifests'
    if manifests.is_dir():
        shutil.copyfile(source, manifests / 'source-snapshot.xml')
        link = root / '.repo/manifest.xml'
        if link.is_symlink():
            link.unlink()
        link.symlink_to('manifests/source-snapshot.xml')
    (root / '.repo/project.list').write_text('\n'.join(sorted(selected)) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('full-source-snapshot.json'))
    parser.add_argument('--cache', type=Path)
    parser.add_argument('--local-parts', type=Path, help='Use existing parts without network')
    parser.add_argument('--groups', help='Comma-separated group numbers for selective restoration tests')
    parser.add_argument('--keep-downloads', action='store_true')
    args = parser.parse_args()
    if not args.manifest.is_file():
        raise SystemExit('Full snapshot migration has not published its index yet: ' + str(args.manifest))
    snapshot = json.loads(args.manifest.read_text())
    identity = hashlib.sha256(args.manifest.read_bytes()).hexdigest()
    root = args.destination.resolve()
    state = root / '.source-restore'
    if root.exists() and any(root.iterdir()) and not (state / 'identity').is_file():
        raise ValueError('Destination must be new or owned by this restorer')
    state.mkdir(parents=True, exist_ok=True)
    marker = state / 'identity'
    if marker.exists() and marker.read_text() != identity:
        raise ValueError('Destination belongs to another source snapshot')
    marker.write_text(identity)
    (root / '.repo').mkdir(exist_ok=True)
    cache = (args.local_parts or args.cache or state / 'downloads').resolve()
    cache.mkdir(parents=True, exist_ok=True)
    groups = snapshot['groups']
    if args.groups:
        numbers = {int(n) for n in args.groups.split(',')}
        groups = [g for g in groups if g['index'] in numbers]
        if len(groups) != len(numbers):
            raise ValueError('Unknown source group')
    selected = {p['path'] for g in groups for p in g.get('projects', []) if p.get('kind', 'project') == 'project'}
    for group in groups:
        receipt = state / ('group-' + str(group['index']))
        if receipt.exists():
            continue
        paths = [safe_path(cache, part['name']) for part in group['parts']]
        for path, part in zip(paths, group['parts']):
            if not args.local_parts:
                url = 'https://github.com/Dingtaiqi/socrates-Arch/releases/download/' + snapshot['release_tag'] + '/' + part['name']
                download(url, path, part)
        verify_parts(paths, group)
        with tempfile.TemporaryDirectory(prefix='extract-', dir=state) as temporary:
            scratch = Path(temporary)
            with JoinedParts(paths) as stream:
                extract(stream, scratch)
            for project in group.get('projects', []):
                install_repository(project, scratch, root)
            if (scratch / 'meta').exists():
                shutil.copytree(scratch / 'meta', state / 'meta', dirs_exist_ok=True)
            copy_tree_files(scratch / 'root-files', root)
            copy_tree_files(scratch / 'extra-files', root)
        receipt.touch()
        if not args.keep_downloads and not args.local_parts:
            for path in paths:
                path.unlink()
        print('GROUP_RESTORED', group['index'], flush=True)
    # Other groups may have been restored by a previous selective invocation.
    selected = {json.loads(p.read_text())['path'] for p in state.glob('repo-*.json')
                if json.loads(p.read_text()).get('kind', 'project') == 'project'}
    apply_overlay(root, selected)
    setup_manifest(root, selected)
    complete = len(list(state.glob('group-*'))) == len(snapshot['groups'])
    record = {'snapshot_sha256': identity, 'project_count': len(selected), 'complete': complete}
    (state / 'RESTORED.json').write_text(json.dumps(record, indent=2) + '\n')
    print('SOURCE_RESTORE_COMPLETE' if complete else 'SELECTIVE_RESTORE_COMPLETE', json.dumps(record))


if __name__ == '__main__':
    main()

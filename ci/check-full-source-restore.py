"""Restore every snapshot group on Linux without retaining a second full tree."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('source_restore', repo / 'evox/restore-source.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)
snapshot_path = repo / 'evox/full-source-snapshot.json'
snapshot = json.loads(snapshot_path.read_text())
identity = hashlib.sha256(snapshot_path.read_bytes()).hexdigest()
report = {'snapshot_sha256': identity, 'groups': [], 'repositories': 0, 'normal_projects': 0,
          'lfs_objects': 0, 'extra_input_files': 0, 'fresh_full_rom_build_verified': False,
          'scope': 'Every group restored independently, including local overlays, Git objects and LFS; not a full ROM compile'}
out = repo / 'out/source-restore-check'
out.mkdir(parents=True, exist_ok=False)
started = time.monotonic()
with tempfile.TemporaryDirectory(prefix='snapshot-check-', dir=os.environ['RUNNER_TEMP']) as temporary:
    temp = Path(temporary)
    common = temp / 'common-meta'
    cache = temp / 'parts'
    cache.mkdir()
    for group in snapshot['groups']:
        paths = []
        for part in group['parts']:
            path = restore.safe_path(cache, part['name'])
            url = 'https://github.com/Dingtaiqi/socrates-Arch/releases/download/' + snapshot['release_tag'] + '/' + part['name']
            restore.download(url, path, part)
            paths.append(path)
        restore.verify_parts(paths, group)
        with tempfile.TemporaryDirectory(prefix='group-', dir=temp) as directory:
            directory = Path(directory)
            scratch, tree = directory / 'archive', directory / 'source'
            tree.mkdir()
            state = tree / '.source-restore'
            state.mkdir()
            (tree / '.repo').mkdir()
            with restore.JoinedParts(paths) as stream:
                restore.extract(stream, scratch)
            if (scratch / 'meta').exists():
                shutil.copytree(scratch / 'meta', common, dirs_exist_ok=True)
            if not common.exists():
                raise ValueError('Snapshot group zero did not include restore metadata')
            shutil.copytree(common, state / 'meta')
            selected = set()
            for project in group.get('projects', []):
                restore.install_repository(project, scratch, tree)
                worktree = restore.safe_path(tree, project['path'])
                restore.run(['git', 'fsck', '--full', '--no-reflogs', '--no-dangling'], cwd=worktree)
                report['repositories'] += 1
                report['lfs_objects'] += project.get('lfs_objects', 0)
                if project.get('kind', 'project') == 'project':
                    report['normal_projects'] += 1
                    selected.add(project['path'])
            restore.copy_tree_files(scratch / 'root-files', tree)
            restore.copy_tree_files(scratch / 'extra-files', tree)
            restore.apply_overlay(tree, selected)
            restore.setup_manifest(tree, selected)
            overlay = json.loads((state / 'overlay/projects.json').read_text())
            for project in overlay:
                if project['path'] not in selected:
                    continue
                for file in project.get('files', []):
                    path = restore.safe_path(tree, project['path'] + '/' + file['path'])
                    if hashlib.sha256(path.read_bytes()).hexdigest() != file['sha256']:
                        raise ValueError('Restored local file differs')
            if group.get('kind') == 'extra_inputs':
                report['extra_input_files'] += group['files']
        for path in paths:
            path.unlink()
        report['groups'].append({'index': group['index'], 'projects': len(group.get('projects', [])),
                                 'compressed_bytes': group['bytes'], 'verified': True})
        print('SOURCE_GROUP_CHECKED', group['index'], 'REPOSITORIES', report['repositories'], flush=True)
        (out / 'progress.json').write_text(json.dumps(report, indent=2) + '\n')
if report['normal_projects'] != snapshot['project_count'] or report['repositories'] != snapshot['project_count'] + 2:
    raise ValueError('Repository coverage differs from the complete snapshot')
report['seconds'] = round(time.monotonic() - started)
report['complete'] = True
(out / 'RESTORE_VALIDATION.json').write_text(json.dumps(report, indent=2) + '\n')
print('ALL_SOURCE_GROUPS_VALIDATED', report['repositories'], flush=True)

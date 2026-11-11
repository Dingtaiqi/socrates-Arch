"""Prepare self-contained pinned Git checkouts from a local object cache.

Compilation remains separate, in a fresh Ubuntu root with an empty output tree.
Requires verified group-zero metadata plus a complete extra-input archive whose
compressed SHA256 matches the public snapshot. Never copies old build outputs.
"""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('restore',here/'restore-source.py')
restore=importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('cache_checkout',type=Path)
parser.add_argument('destination',type=Path)
parser.add_argument('extra_archive',type=Path)
args=parser.parse_args()
cache=args.cache_checkout.resolve();root=args.destination.resolve();extra=args.extra_archive.resolve()
assert root!=cache and not root.is_relative_to(cache) and not cache.is_relative_to(root)
assert not (root/'out').exists(), 'Refusing a warm output directory'
index=here/'full-source-snapshot.json'
snapshot=json.loads(index.read_text());identity=hashlib.sha256(index.read_bytes()).hexdigest()
state=root/'.source-restore'
assert (state/'identity').read_text()==identity
assert (state/'meta/porting-overlay.tar.gz').is_file() and (state/'meta/manifest.lock.xml').is_file()
assert not list(state.glob('repo-*.pending')), 'Finish or inspect an interrupted checkout first'
env={**os.environ,'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null',
     'GIT_OPTIONAL_LOCKS':'0','GIT_LFS_SKIP_SMUDGE':'1','GIT_ATTR_NOSYSTEM':'1',
     'GIT_CONFIG_COUNT':'3','GIT_CONFIG_KEY_0':'safe.directory','GIT_CONFIG_VALUE_0':'*',
     'GIT_CONFIG_KEY_1':'pack.threads','GIT_CONFIG_VALUE_1':'2',
     'GIT_CONFIG_KEY_2':'core.fsmonitor','GIT_CONFIG_VALUE_2':'false'}
restore.ENV=env
def run(command,cwd=None):
    return subprocess.check_output(command,cwd=cwd,env=env,stderr=subprocess.PIPE)
def digest(path):
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(8*1024*1024),b''):result.update(block)
    return result.hexdigest()

started=time.monotonic()
extra_group=next(g for g in snapshot['groups'] if g.get('kind')=='extra_inputs')
assert extra.stat().st_size==extra_group['bytes'] and digest(extra)==extra_group['sha256']
records=[]
progress=state/'GIT_CACHE_PROGRESS.json'
original_groups=sorted(int(p.name.split('-')[1]) for p in state.glob('group-*'))
def prepare(project,scratch):
    if (state/('repo-'+project['id']+'.json')).exists():return
    source=restore.safe_path(cache,project['path'])
    destination=scratch/'mirrors'/(project['id']+'.git')
    run(['git','clone','--quiet','--bare','--no-local','--depth','1','file://'+str(source),str(destination)])
    git=['git','--git-dir='+str(destination)]
    assert run(git+['rev-parse','HEAD']).decode().strip()==project['head'], 'Cached HEAD changed: '+project['path']
    assert not (destination/'objects/info/alternates').exists()
    # Select actual filter=lfs files, leaving literal pointer test data untouched.
    listing=run(['git','-C',str(source),'lfs','ls-files','--long','HEAD']).decode().splitlines()
    required=[]
    if listing:
        run(git+['read-tree','HEAD'])
        for line in listing:
            name=line[67:]
            attrs=run(git+['-c','core.attributesFile=/dev/null','check-attr','--cached','-z','filter','--',name])
            if attrs.split(b'\0')[2]==b'lfs':required.append((line[:64],name))
        (destination/'index').unlink(missing_ok=True)
    assert len(required)==project.get('lfs_objects',0)
    if required:
        settings=run(['git','-C',str(source),'lfs','env']).decode().splitlines()
        media=Path(next(l.split('=',1)[1] for l in settings if l.startswith('LocalMediaDir=')))
        for oid,name in required:
            candidates=[media/oid[:2]/oid[2:4]/oid,restore.safe_path(cache,project['path']+'/'+name)]
            original=next((p for p in candidates if p.is_file() and digest(p)==oid),None)
            assert original is not None, 'Pinned LFS input unavailable: '+project['path']+'/'+name
            target=destination/'lfs/objects'/oid[:2]/oid[2:4]/oid
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(original,target)
    run(git+['remote','set-url','origin',project['url']])

for group in snapshot['groups']:
    if not group.get('projects'):continue
    with tempfile.TemporaryDirectory(prefix='git-cache-',dir=state) as directory:
        scratch=Path(directory);(scratch/'mirrors').mkdir()
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda p:prepare(p,scratch),group['projects']))
        for project in group['projects']:
            restore.install_repository(project,scratch,root)
            worktree=restore.safe_path(root,project['path'])
            assert run(['git','rev-parse','HEAD'],cwd=worktree).decode().strip()==project['head']
            run(['git','fsck','--full','--no-reflogs','--no-dangling'],cwd=worktree)
            run(['git','diff','--exit-code','HEAD','--'],cwd=worktree)
            gitdir=Path(run(['git','rev-parse','--absolute-git-dir'],cwd=worktree).decode().strip())
            assert gitdir.resolve().is_relative_to(root) and not (gitdir/'objects/info/alternates').exists()
            records.append({'path':project['path'],'head':project['head'],'git_full_fsck':'passed',
                            'lfs_objects':project.get('lfs_objects',0),'self_contained':True})
    progress.write_text(json.dumps({'repositories':len(records),'group':group['index'],
                                   'seconds':round(time.monotonic()-started)})+'\n')
    print('PINNED_GIT_CACHE_GROUP_READY',group['index'],'REPOSITORIES',len(records),flush=True)

with tempfile.TemporaryDirectory(prefix='extra-cache-',dir=state) as directory:
    with extra.open('rb') as stream:restore.extract(stream,Path(directory))
    restore.copy_tree_files(Path(directory)/'extra-files',root)
selected={p['path'] for g in snapshot['groups'] for p in g['projects'] if p.get('kind','project')=='project'}
restore.apply_overlay(root,selected)
restore.setup_manifest(root,selected)
assert len(records)==1267 and len(selected)==snapshot['project_count']==1265
proof={'snapshot_sha256':identity,'complete':True,'project_count':len(selected),
       'method':'self-contained shallow Git from local immutable object cache',
       'repositories':records,'git_full_fsck':'passed','no_git_alternates':True,
       'no_old_build_outputs_copied':True,'extra_archive_sha256':extra_group['sha256'],
       'extra_files_covered_by_exact_archive_hash':extra_group['files'],
       'public_archive_groups_previously_restored':original_groups,
       'seconds':round(time.monotonic()-started)}
(state/'GIT_CACHE_VALIDATION.json').write_text(json.dumps(proof,indent=2)+'\n')
(state/'RESTORED.json').write_text(json.dumps({k:v for k,v in proof.items() if k!='repositories'},indent=2)+'\n')
(state/'.find-ignore').touch()
if os.geteuid()==0:
    assert root.resolve()==root and not root.is_symlink()
    subprocess.run(['chown','-R','--no-dereference','1000:1000',str(root)],check=True)
print('SELF_CONTAINED_PINNED_SOURCE_READY',len(records),'SECONDS',proof['seconds'],flush=True)

"""Read-only export of the EvoX checkout and server-owned porting sources."""
import concurrent.futures, hashlib, json, os, pathlib, subprocess, tarfile, time
ROOT=pathlib.Path('/build/evox')
OUT=pathlib.Path('/home/qinghuo/source_exports_20261110/capture-v1')
OUT.mkdir(mode=0o700,exist_ok=False)
ENV=os.environ.copy();ENV.update(GIT_OPTIONAL_LOCKS='0',GIT_CONFIG_COUNT='2',GIT_CONFIG_KEY_0='safe.directory',GIT_CONFIG_VALUE_0='*',GIT_CONFIG_KEY_1='core.fsmonitor',GIT_CONFIG_VALUE_1='false',LC_ALL='C.UTF-8')
def cmd(args,cwd=None):
 return subprocess.run(args,cwd=cwd,env=ENV,capture_output=True,timeout=300)
def write(p,data):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
repo=str(ROOT/'.repo/repo/repo')
m=cmd([repo,'manifest','-r','-o',str(OUT/'manifest.lock.xml')],ROOT)
write(OUT/'manifest-command.txt',m.stdout+m.stderr)
# Preserve manifest sources, including local changes and the original branches.
for p in (ROOT/'.repo').glob('local_manifests/*.xml'):write(OUT/'manifests/local'/p.name,p.read_bytes())
for p in (ROOT/'.repo/manifests').glob('*.xml'):write(OUT/'manifests/upstream'/p.name,p.read_bytes())
paths=(ROOT/'.repo/project.list').read_text().splitlines();print('PROJECTS',len(paths),'MANIFEST_RC',m.returncode,flush=True)
source_ext={'.c','.cpp','.cc','.h','.hpp','.java','.kt','.rs','.py','.sh','.rc','.mk','.bp','.xml','.json','.ini','.cfg','.conf','.txt','.patch','.diff','.aidl','.dts','.dtsi','.def','.map','.in','.cmake','.md','.S','.s','.go','.mod','.sum','.csv'}
records=[]
def capture(name):
 work=ROOT/name;ident=hashlib.sha256(name.encode()).hexdigest()[:20];dst=OUT/'projects'/ident
 git=['git','-C',str(work)]
 head=cmd(git+['rev-parse','HEAD'])
 entry={'path':name,'id':ident,'head_rc':head.returncode}
 if head.returncode:
  entry['error']=head.stderr.decode(errors='replace')[:300];return entry
 entry['head']=head.stdout.decode().strip()
 diff=cmd(git+['diff','--binary','--no-ext-diff','--no-textconv','HEAD'])
 entry['diff_rc']=diff.returncode
 if diff.stdout:write(dst/'tracked.patch',diff.stdout);entry['patch_bytes']=len(diff.stdout)
 changed=cmd(git+['diff','--name-only','-z','HEAD']).stdout.split(b'\0')
 untracked=cmd(git+['ls-files','--others','--exclude-standard','-z']).stdout.split(b'\0')
 files=[];excluded=[]
 for raw in sorted(set(changed+untracked)):
  if not raw:continue
  rel=os.fsdecode(raw);p=work/rel
  if not p.exists() or p.is_symlink():continue
  if not p.is_file():continue
  size=p.stat().st_size
  # All tracked changes are kept; untracked exports are limited to source/config.
  if raw in untracked and (size>16*1024*1024 or (p.suffix not in source_ext and p.name not in ('LICENSE','NOTICE','Android.bp','Android.mk','Makefile','evolution.dependencies'))):
   excluded.append({'path':rel,'bytes':size});continue
  if p.suffix.lower() in {'.pk8','.pem','.key','.p12','.jks','.keystore'}:
   excluded.append({'path':rel,'reason':'private key / signing material'});continue
  if p.is_relative_to(work) and '..' not in pathlib.PurePosixPath(rel).parts:
   data=p.read_bytes();write(dst/'files'/rel,data);files.append({'path':rel,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'untracked':raw in untracked})
 entry['files']=files;entry['excluded_untracked']=excluded
 # Preserve local commits that a fixed remote revision alone cannot restore.
 unique=cmd(git+['rev-list','--count','HEAD','--not','--remotes'])
 entry['local_commit_count']=int(unique.stdout or b'0') if unique.returncode==0 else None
 if entry['local_commit_count']:
  dst.mkdir(parents=True,exist_ok=True)
  refs=cmd(git+['for-each-ref','--format=%(refname)','refs/remotes']).stdout.decode().splitlines()
  args=git+['bundle','create',str(dst/'local-commits.bundle'),'HEAD']+['^'+r for r in refs]
  bundle=cmd(args);entry['bundle_rc']=bundle.returncode
  if bundle.returncode:write(dst/'bundle-error.txt',bundle.stderr)
 if files or diff.stdout or entry['local_commit_count']:write(dst/'project.json',json.dumps(entry,indent=2).encode())
 return entry
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 for future in concurrent.futures.as_completed([pool.submit(capture,p) for p in paths]):
  try:r=future.result()
  except Exception as e:r={'error':type(e).__name__+': '+str(e)}
  records.append(r)
  if len(records)%100==0:print('CAPTURED_PROJECTS',len(records),flush=True)
write(OUT/'projects.json',json.dumps(sorted(records,key=lambda r:r.get('path','')),indent=2).encode())
# Flat server build/patch scripts are the missing inputs of the bNN image chain.
home=pathlib.Path('/home/qinghuo')
for p in home.iterdir():
 if not p.is_file() or p.suffix not in source_ext:continue
 if p.name.startswith(('srv_','patch_','gen_','fix_','dsu_','_build_','_setup_','_weston_')) or p.name in ('file_paths.h','libgsi_private.h'):
  if p.stat().st_size<16*1024*1024:write(OUT/'server-scripts'/p.name,p.read_bytes())
# Original isolated GPU build recipes, package locks and cross-toolchain metadata.
work=home/'kde_dsu_20261109'
for p in work.iterdir():
 if p.is_file() and p.suffix in source_ext and p.stat().st_size<16*1024*1024:write(OUT/'arch-build'/p.name,p.read_bytes())
for dirname in ['glslang-14.3.0','mesa-26.2.6']:
 p=work/dirname
 if (p/'.git').exists():
  write(OUT/'arch-build'/f'{dirname}-git-head.txt',cmd(['git','-C',str(p),'rev-parse','HEAD']).stdout)
# Additional native sources and package identity metadata; no rootfs/user data.
for folder in [pathlib.Path('/build/arch/native'),home/'server_scripts']:
 if folder.is_dir():
  for p in folder.iterdir():
   if p.is_file() and p.suffix in source_ext and p.stat().st_size<16*1024*1024:
    write(OUT/'additional-sources'/folder.name/p.name,p.read_bytes())
for p in pathlib.Path('/build/arch/rootfs-weston/var/lib/pacman/local').glob('*/desc'):
 write(OUT/'arch-packages'/p.parent.name/'desc',p.read_bytes())
summary={'manifest_rc':m.returncode,'projects':len(records),'git_failures':sum(r.get('head_rc',1)!=0 for r in records),'modified_projects':sum(bool(r.get('patch_bytes')) for r in records),'exported_files':sum(len(r.get('files',[])) for r in records),'local_commit_projects':sum(bool(r.get('local_commit_count')) for r in records),'errors':[r for r in records if 'path' not in r]}
write(OUT/'summary.json',json.dumps(summary,indent=2).encode())
archive=OUT.parent/'server-source-capture-v1.tar.gz'
with tarfile.open(archive,'w:gz') as t:t.add(OUT,arcname='capture')
h=hashlib.sha256()
with archive.open('rb') as f:
 for block in iter(lambda:f.read(4194304),b''):h.update(block)
write(archive.with_suffix(archive.suffix+'.sha256'),(h.hexdigest()+'  '+archive.name+'\n').encode())
for folder,ds,fs in os.walk(OUT):
 os.chown(folder,1000,1000)
 for n in fs:os.chown(os.path.join(folder,n),1000,1000)
for p in [archive,archive.with_suffix(archive.suffix+'.sha256')]:os.chown(p,1000,1000);os.chmod(p,0o600)
write(OUT.parent/'CAPTURE_READY.json',json.dumps({'summary':summary,'archive':str(archive),'bytes':archive.stat().st_size,'sha256':h.hexdigest()},indent=2).encode())
os.chown(OUT.parent/'CAPTURE_READY.json',1000,1000)
print('EXPORT_SUMMARY',json.dumps(summary),flush=True)
print('EXPORT_ARCHIVE',str(archive),archive.stat().st_size,h.hexdigest(),flush=True)

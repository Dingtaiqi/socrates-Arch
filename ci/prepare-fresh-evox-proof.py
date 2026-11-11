"""Prepare resumable ROM parts and evidence on the build host, without deleting outputs."""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

work,output,console=map(lambda p:Path(p).resolve(),sys.argv[1:])
assert (work/'.evox-fresh-workspace').read_text().strip()=='socrates-evox-fresh-v1'
report=json.loads((work/'FULL_BUILD_RESULT.json').read_text())
assert report['success'] and report['fresh_output_started_empty'] and report['target']=='evolution'
assert report['source_restore']['complete'] and report['source_restore']['project_count']==1265
assert report['fresh_ubuntu_root'] and not report['original_checkout_mounted']
assert len(report['rom_packages'])==1
package=work/report['rom_packages'][0]['path']
assert package.resolve().is_relative_to((work/'build/source/out/target/product/socrates').resolve())
output.mkdir(mode=0o700,parents=True,exist_ok=True)
manifest=output/'evox-fresh-rom.zip.manifest.json'
if not manifest.exists():
    assert shutil.disk_usage(output).free>package.stat().st_size+2*1024**3, 'Not enough room to pack ROM'
    subprocess.run([sys.executable,str(Path(__file__).with_name('bundle.py')),'pack',str(package),str(output),
                    '--name','evox-fresh-rom.zip'],check=True)
image=json.loads(manifest.read_text())
assert image['sha256']==report['rom_packages'][0]['sha256']
assert image['bytes']==report['rom_packages'][0]['bytes']
for source,name in [(work/'FULL_BUILD_RESULT.json','FULL_BUILD_RESULT.json'),
                    (work/'STARTED.json','STARTED.json'),
                    (work/'logs/container-packages.tsv','container-packages.tsv'),
                    (work/'build/source/.source-restore/RESTORED.json','SOURCE_RESTORED.json')]:
    shutil.copyfile(source,output/name)
prefetch=work/'build/source/.source-restore/PREFETCH_RESULT.json'
if prefetch.exists():shutil.copyfile(prefetch,output/'PREFETCH_RESULT.json')
cache=work/'build/source/.source-restore/GIT_CACHE_VALIDATION.json'
if cache.exists():shutil.copyfile(cache,output/'GIT_CACHE_VALIDATION.json')
with console.open('rb') as source,(output/'full-build.console.log.gz').open('wb') as target:
    with gzip.GzipFile(filename='',mode='wb',fileobj=target,compresslevel=1,mtime=0) as compressed:
        shutil.copyfileobj(source,compressed,1024*1024)
assets=[]
for path in sorted(output.iterdir()):
    if path.name=='ASSETS.json':continue
    assert path.is_file() and path.stat().st_size<2*1024**3
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(4*1024*1024),b''):digest.update(block)
    path.chmod(0o600)
    assets.append({'name':path.name,'bytes':path.stat().st_size,'sha256':digest.hexdigest()})
(output/'ASSETS.json').write_text(json.dumps({'build_result':report,'assets':assets},indent=2)+'\n')
(output/'ASSETS.json').chmod(0o600)
print('FRESH_EVOX_ARCHIVE_READY',len(assets),sum(a['bytes'] for a in assets),flush=True)

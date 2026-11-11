"""Supervise the isolated restore/full build and record actual success evidence."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import zipfile

work,recipe=map(lambda p:Path(p).resolve(),sys.argv[1:])
assert (work/'.evox-fresh-workspace').read_text().strip()=='socrates-evox-fresh-v1'
root=work/'ubuntu'
source=work/'build/source'
out=source/'out'
if out.exists() and any(out.iterdir()):
    raise SystemExit('Refusing a warm output tree; use a new workspace or explicitly clear its generated output')
record={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'recipe_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=recipe,text=True).strip(),
        'snapshot_sha256':hashlib.sha256((recipe/'evox/full-source-snapshot.json').read_bytes()).hexdigest(),
        'target':'evolution','device':'socrates','fresh_output_started_empty':True,
        'fresh_ubuntu_root':True,'original_checkout_mounted':False,
        'ubuntu_base_sha256':'242cd8898b33ea806ef5f13b1076ed7c76f9f989d18384452f7166692438ff1a',
        'phone_operations':False,'success':False}
jobs=os.environ.get('BUILD_JOBS','16')
if not jobs.isdigit() or not 1<=int(jobs)<=32:raise SystemExit('Invalid BUILD_JOBS')
proxy=os.environ.get('FRESH_DOWNLOAD_PROXY')
network=['HTTPS_PROXY='+proxy,'HTTP_PROXY='+proxy,'NO_PROXY=localhost,127.0.0.1'] if proxy else []
record.update(parallel_jobs=int(jobs),download_proxy_used=bool(proxy))
(work/'STARTED.json').write_text(json.dumps(record,indent=2)+'\n')
command=['chroot',str(root),'/usr/sbin/runuser','-u','builder','--','/usr/bin/env','-i',
         'HOME=/home/builder','USER=builder','LOGNAME=builder','SHELL=/bin/bash',
         'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
         'LANG=C.UTF-8','LC_ALL=C.UTF-8','TMPDIR=/tmp','BUILD_JOBS='+jobs,
         'GIT_CONFIG_NOSYSTEM=1','GIT_CONFIG_GLOBAL=/dev/null','CCACHE_DISABLE=1',*network,
         '/bin/bash','/recipes/build.sh','evox','/workspace/source','evolution']
print('FRESH_RESTORE_AND_FULL_BUILD_STARTED',flush=True)
started=time.monotonic()
process=subprocess.Popen(command,start_new_session=True)
record['process_pid']=process.pid
reason=None
reported=0
while process.poll() is None:
    free=shutil.disk_usage(work).free
    if free<8*1024**3:reason='disk_below_8_gib'
    if time.monotonic()-started>24*3600:reason='24_hour_runtime_limit'
    if reason:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL);process.wait()
        break
    if time.monotonic()-reported>=60:
        report={'elapsed_seconds':int(time.monotonic()-started),'free_gib':round(free/1024**3,2),
                'restored_groups':len(list((source/'.source-restore').glob('group-*'))),
                'compile_started':out.exists()}
        (work/'PROGRESS.json').write_text(json.dumps(report,indent=2)+'\n')
        print('FRESH_BUILD_PROGRESS',json.dumps(report),flush=True)
        reported=time.monotonic()
    time.sleep(5)
record.update(returncode=process.returncode,stop_reason=reason,
              elapsed_seconds=round(time.monotonic()-started),
              finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
receipt=source/'.source-restore/RESTORED.json'
if receipt.exists():record['source_restore']=json.loads(receipt.read_text())
if process.returncode==0:
    restored=record['source_restore']
    assert restored['complete'] and restored['project_count']==1265
    assert restored['snapshot_sha256']==record['snapshot_sha256']
    products=out/'target/product/socrates'
    packages=sorted(products.glob('EvolutionX-*.zip'))
    assert packages, 'Full ROM target did not produce a package'
    record['rom_packages']=[]
    for package in packages:
        digest=hashlib.sha256()
        with package.open('rb') as stream:
            for block in iter(lambda:stream.read(8*1024*1024),b''):digest.update(block)
        with zipfile.ZipFile(package) as archive:
            assert archive.testzip() is None
            assert 'payload.bin' in archive.namelist()
        record['rom_packages'].append({'path':str(package.relative_to(work)),
             'bytes':package.stat().st_size,'sha256':digest.hexdigest(),'zip_crc_verified':True})
    record['success']=True
(work/'FULL_BUILD_RESULT.json').write_text(json.dumps(record,indent=2)+'\n')
print('FRESH_FULL_BUILD_RESULT',json.dumps(record),flush=True)
raise SystemExit(0 if record['success'] else 1)

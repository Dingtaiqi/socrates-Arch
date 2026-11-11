"""Download public source on GitHub and deliver one verified group to fresh DSU build host."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import posixpath
import tempfile
import time

import paramiko

repo=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('restore',repo/'evox/restore-source.py')
restore=importlib.util.module_from_spec(spec);spec.loader.exec_module(restore)
index=repo/'evox/full-source-snapshot.json'
snapshot=json.loads(index.read_text())
identity=hashlib.sha256(index.read_bytes()).hexdigest()
state='/home/qinghuo/evox-fresh-20261111/build/source/.source-restore'
cache=state+'/downloads'
client=paramiko.SSHClient()
for line in os.environ['BUILD_KNOWN_HOSTS'].splitlines():
    entry=paramiko.hostkeys.HostKeyEntry.from_line(line)
    if entry:
        for name in entry.hostnames:client.get_host_keys().add(name,entry.key.get_name(),entry.key)
client.set_missing_host_key_policy(paramiko.RejectPolicy())
started=time.monotonic()
report={'snapshot_sha256':identity,'groups':[],'bytes_sent':0,'complete':False,
        'run_url':'https://github.com/'+os.environ['GITHUB_REPOSITORY']+'/actions/runs/'+os.environ['GITHUB_RUN_ID']}
try:
    client.connect(os.environ['BUILD_HOST'],port=int(os.environ['BUILD_PORT']),username=os.environ['BUILD_USER'],
                   password=os.environ['BUILD_PASSWORD'],allow_agent=False,look_for_keys=False,
                   timeout=15,banner_timeout=30,auth_timeout=30,channel_timeout=180)
    client.get_transport().set_keepalive(15)
    sftp=client.open_sftp();sftp.get_channel().settimeout(180)
    assert sftp.open(state+'/identity').read().decode()==identity
    def exists(path):
        try:sftp.stat(path);return True
        except FileNotFoundError:return False
    with tempfile.TemporaryDirectory(prefix='evox-prefetch-') as directory:
        directory=Path(directory)
        for group in snapshot['groups']:
            receipt=state+'/group-'+str(group['index'])
            if exists(receipt):
                print('GROUP_ALREADY_RESTORED',group['index'],flush=True)
                continue
            for part in group['parts']:
                assert Path(part['name']).name==part['name']
                target=cache+'/'+part['name']
                if exists(target):
                    assert sftp.stat(target).st_size==part['bytes']
                    continue
                local=directory/part['name']
                restore.download('https://github.com/Dingtaiqi/socrates-Arch/releases/download/'+snapshot['release_tag']+'/'+part['name'],local,part)
                digest=hashlib.sha256()
                with local.open('rb') as stream:
                    for block in iter(lambda:stream.read(4*1024*1024),b''):digest.update(block)
                assert digest.hexdigest()==part['sha256']
                sent_at=time.monotonic()
                last=[0]
                def progress(done,total):
                    if done-last[0]>=64*1024*1024:
                        print('PREFETCH_PROGRESS',part['name'],done,total,round(done/max(time.monotonic()-sent_at,.01)),flush=True)
                        last[0]=done
                temporary=target+'.cloud-uploading'
                sftp.put(str(local),temporary,callback=progress,confirm=True)
                sftp.rename(temporary,target)
                seconds=time.monotonic()-sent_at
                report['bytes_sent']+=part['bytes']
                print('SOURCE_PART_DELIVERED',part['name'],part['bytes'],'seconds',round(seconds,2),flush=True)
                local.unlink()
            until=time.monotonic()+3600
            while not exists(receipt):
                if time.monotonic()>until:raise TimeoutError('Consumer did not verify group '+str(group['index']))
                if time.monotonic()-started>5*3600:raise TimeoutError('Prefetch session limit; rerun to resume')
                time.sleep(2)
            # Receipt follows the restorer's complete checksum and checkout pass.
            for part in group['parts']:
                target=cache+'/'+part['name']
                if exists(target):sftp.remove(target)
            report['groups'].append(group['index'])
            print('SOURCE_GROUP_DELIVERED_AND_VERIFIED',group['index'],flush=True)
        until=time.monotonic()+300
        while True:
            if exists(state+'/RESTORED.json'):
                restored=json.loads(sftp.open(state+'/RESTORED.json').read())
                if restored['complete']:
                    assert restored['snapshot_sha256']==identity
                    break
            if time.monotonic()>until:raise TimeoutError('Final restoration receipt absent')
            time.sleep(2)
        report.update(complete=True,seconds=round(time.monotonic()-started),source_restore=restored)
        with sftp.open(state+'/PREFETCH_RESULT.json','w') as output:output.write(json.dumps(report,indent=2)+'\n')
        print('ALL_SOURCE_GROUPS_PREFETCHED_AND_RESTORED',json.dumps(report),flush=True)
finally:client.close()

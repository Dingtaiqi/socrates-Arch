"""Wait for the independent build and prepare its archive on the host."""
import hashlib,json,os,shlex,time
from pathlib import Path
import paramiko

work='/home/qinghuo/evox-fresh-20261111'
identity=hashlib.sha256((Path(__file__).resolve().parents[1]/'evox/full-source-snapshot.json').read_bytes()).hexdigest()
client=paramiko.SSHClient()
for line in os.environ['BUILD_KNOWN_HOSTS'].splitlines():
    entry=paramiko.hostkeys.HostKeyEntry.from_line(line)
    if entry:
        for name in entry.hostnames:client.get_host_keys().add(name,entry.key.get_name(),entry.key)
client.set_missing_host_key_policy(paramiko.RejectPolicy())
try:
    client.connect(os.environ['BUILD_HOST'],port=int(os.environ['BUILD_PORT']),username=os.environ['BUILD_USER'],
                   password=os.environ['BUILD_PASSWORD'],allow_agent=False,look_for_keys=False,
                   timeout=15,banner_timeout=30,auth_timeout=30)
    client.get_transport().set_keepalive(15)
    sftp=client.open_sftp();sftp.get_channel().settimeout(180)
    started=time.monotonic();reported=0
    while True:
        try:
            with sftp.open(work+'/FULL_BUILD_RESULT.json') as stream:result=json.loads(stream.read())
        except (FileNotFoundError,json.JSONDecodeError):result=None
        if result is not None:
            assert result['snapshot_sha256']==identity
            if not result['success']:raise RuntimeError('Full ROM build failed; inspect its console log before archiving')
            assert result['fresh_output_started_empty'] and result['fresh_ubuntu_root']
            assert result['target']=='evolution' and not result['original_checkout_mounted']
            print('INDEPENDENT_FULL_ROM_BUILD_SUCCEEDED',result['elapsed_seconds'],flush=True)
            break
        elapsed=time.monotonic()-started
        if elapsed>5.5*3600:raise TimeoutError('Build still running; archive workflow can be rerun without restarting it')
        if elapsed-reported>=300:
            print('WAITING_FOR_INDEPENDENT_ROM_BUILD',round(elapsed),'seconds',flush=True);reported=elapsed
        time.sleep(30)
    sftp.close()
    args=['python3','/home/qinghuo/evox-fresh-recipes-20261111/ci/prepare-fresh-evox-proof.py',work,
          '/home/qinghuo/evox-fresh-archive-20261111','/home/qinghuo/evox-fresh-control-20261111/full-build.console.log']
    stdin,stdout,stderr=client.exec_command(shlex.join(args),timeout=900)
    stdin.channel.shutdown_write()
    for line in stdout:print(line,end='',flush=True)
    error=stderr.read().decode(errors='replace')
    if error:print(error,flush=True)
    if stdout.channel.recv_exit_status():raise RuntimeError('Archive preparation failed')
finally:client.close()

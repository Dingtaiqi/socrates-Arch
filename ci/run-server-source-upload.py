"""Use a temporary GitHub job token; only control traffic passes through CI."""
import json
import os
import paramiko

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
    program = os.environ.get('SERVER_UPLOAD_PROGRAM', 'upload_sources_v2.py')
    if program not in ('upload_sources_v2.py', 'upload_full_sources.py', 'upload_full_sources_v2.py',
                        'probe_server_upload.py'):
        raise SystemExit('Unsupported server upload program')
    stdin, stdout, stderr = client.exec_command(
        'timeout -k 15s 19800s python3 -u /home/qinghuo/source_exports_20261110/' + program, timeout=180)
    stdin.write(json.dumps({'token': os.environ['GH_TOKEN'],
                            'repository': os.environ['GITHUB_REPOSITORY'],
                            'run_id': os.environ['GITHUB_RUN_ID'],
                            'run_url': 'https://github.com/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID'],
                            'commit': os.environ['GITHUB_SHA']}) + '\n')
    stdin.flush()
    stdout.channel.settimeout(3600)
    complete = False
    for line in stdout:
        print(line, end='', flush=True)
        if line.startswith('FULL_SOURCE_PUBLISHED '):
            complete = True
    error = stderr.read().decode()
    if error:
        print(error)
    code = stdout.channel.recv_exit_status()
    if code:
        raise SystemExit(code)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('complete=' + str(complete).lower() + '\n')
finally:
    client.close()

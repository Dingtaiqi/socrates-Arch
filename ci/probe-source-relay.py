"""Measure a bounded, read-only server-to-runner transfer of public build input."""
import json
import os
import time

import paramiko

client = paramiko.SSHClient()
for line in os.environ['BUILD_KNOWN_HOSTS'].splitlines():
    entry = paramiko.hostkeys.HostKeyEntry.from_line(line)
    if entry:
        for name in entry.hostnames:
            client.get_host_keys().add(name, entry.key.get_name(), entry.key)
client.set_missing_host_key_policy(paramiko.RejectPolicy())
expected = 64 * 1024 * 1024
try:
    client.connect(os.environ['BUILD_HOST'], port=int(os.environ['BUILD_PORT']),
                   username=os.environ['BUILD_USER'], password=os.environ['BUILD_PASSWORD'],
                   allow_agent=False, look_for_keys=False, timeout=15,
                   banner_timeout=30, auth_timeout=30)
    client.get_transport().set_keepalive(20)
    _, stdout, stderr = client.exec_command(
        'head -c 67108864 /home/qinghuo/source_exports_20261110/arch-inputs-v1/'
        'arch-turnip-build-inputs-20261110.tar.gz', timeout=180)
    stdout.channel.settimeout(180)
    started, received = time.monotonic(), 0
    while True:
        block = stdout.read(1024 * 1024)
        if not block:
            break
        received += len(block)
    if stdout.channel.recv_exit_status() or received != expected:
        raise RuntimeError('Bounded source-relay probe did not complete')
    seconds = time.monotonic() - started
    print('SOURCE_RELAY_PROBE', json.dumps({'bytes': received, 'seconds': round(seconds, 2),
          'mib_per_second': round(received / 1048576 / seconds, 2)}), flush=True)
finally:
    client.close()

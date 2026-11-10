"""Create a de-personalized build base in a disposable GitHub runner copy."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

if os.geteuid() != 0:
    raise SystemExit('Run this image preparation step with sudo on the disposable runner')
repo = Path.cwd().resolve()
image = (repo / 'inputs/system.img').resolve()
work = repo / 'out/arch-base-work'
work.mkdir(parents=True, exist_ok=False)
mount = work / 'mounted'
mount.mkdir()
root = work / 'rootfs'
root.mkdir()
placeholder = '00000000-0000-4000-8000-000000000000'
stats = {'removed_paths': 0, 'locked_accounts': 0, 'removed_login_accounts': 0}

def run(args, allowed=(0,)):
    result = subprocess.run(args)
    if result.returncode not in allowed:
        raise RuntimeError('Image tool failed: ' + args[0])

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()

def owned(base, relative):
    path = base / relative
    if not path.parent.resolve().is_relative_to(base.resolve()):
        raise ValueError('Refusing an image path through an external symlink')
    return path

def remove(base, relative):
    path = owned(base, relative)
    if path.is_symlink():
        path.unlink()
    elif path.is_dir():
        assert path.resolve().is_relative_to(base.resolve())
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()
    else:
        return
    stats['removed_paths'] += 1

def write(base, relative, text, mode=0o644):
    path = owned(base, relative)
    if path.is_symlink():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)

def remove_keys(base):
    for directory, dirs, files in os.walk(base, followlinks=False):
        dirs[:] = [d for d in dirs if not (Path(directory) / d).is_symlink()]
        for name in files:
            if name in ('authorized_keys', 'authorized_keys2', 'known_hosts', 'adb_keys') or name.startswith('ssh_host_'):
                remove(base, (Path(directory) / name).relative_to(base))

run(['mount', '-o', 'loop', str(image), str(mount)])
try:
    source = mount / 'system/arch-rootfs.erofs'
    if digest(source) != '7afa94d0b226a1a22c79fb82ca2c12256d258d5257c5eb8dec7685281f070023':
        raise ValueError('Original rootfs does not match the verified baseline')
    run(['fsck.erofs', '--extract=' + str(root), str(source)])
    for path in ['root', 'home', 'tmp', 'run', 'var/log', 'var/cache/pacman/pkg',
                 'etc/pacman.d/gnupg', 'etc/NetworkManager/system-connections',
                 'etc/wpa_supplicant', 'etc/wpa_supplicant.conf', 'etc/iwd', 'etc/connman',
                 'etc/netctl', 'etc/ppp',
                 'etc/ssl/private', 'etc/credstore', 'etc/credstore.encrypted',
                 'etc/shadow-', 'etc/gshadow-', 'etc/passwd-', 'etc/group-',
                 'var/lib/NetworkManager', 'var/lib/iwd', 'var/lib/connman', 'var/lib/bluetooth',
                 'var/lib/dhcpcd', 'var/lib/systemd/random-seed', 'var/lib/urandom/random-seed',
                 'var/lib/systemd/credential.secret', 'var/lib/dbus/machine-id']:
        remove(root, path)
    for path, mode in [('root', 0o700), ('home', 0o755), ('tmp', 0o1777), ('run', 0o755)]:
        directory = owned(root, path)
        directory.mkdir(parents=True, exist_ok=True)
        directory.chmod(mode)
    passwd = owned(root, 'etc/passwd')
    keep = set()
    lines = []
    for line in passwd.read_text().splitlines():
        fields = line.split(':')
        if len(fields) != 7:
            raise ValueError('Malformed passwd file')
        uid = int(fields[2])
        if 1000 <= uid < 65534:
            stats['removed_login_accounts'] += 1
            continue
        fields[4] = ''
        keep.add(fields[0])
        lines.append(':'.join(fields))
    write(root, 'etc/passwd', '\n'.join(lines) + '\n')
    for filename in ['shadow', 'gshadow']:
        path = owned(root, 'etc/' + filename)
        if not path.exists():
            continue
        lines = []
        for line in path.read_text().splitlines():
            fields = line.split(':')
            if filename == 'shadow' and fields[0] not in keep:
                continue
            fields[1] = '!'
            stats['locked_accounts'] += 1
            lines.append(':'.join(fields))
        write(root, 'etc/' + filename, '\n'.join(lines) + '\n', 0o600)
    for name in ['subuid', 'subgid', 'machine-id']:
        write(root, 'etc/' + name, '')
    write(root, 'etc/hostname', 'socrates-arch\n')
    write(root, 'etc/hosts', '127.0.0.1 localhost\n::1 localhost\n')
    remove_keys(root)
    # Config scripts with literal credentials require review, rather than
    # silently changing code used by the desktop.
    credential = re.compile(r'''(?mi)^\s*(?:export\s+)?(?:PASS|PASSWORD|SUDO_PASS(?:WORD)?|WIFI_SSID|WIFI_PASS)\s*=\s*(['"])([^'"\r\n]+)\1''')
    for directory in ['etc', 'opt/kde-dsu']:
        for path in (root / directory).rglob('*'):
            if path.is_symlink() or not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
                continue
            try:
                text = path.read_text()
            except UnicodeError:
                continue
            if any(not m[2].startswith(('$', 'REDACTED')) for m in credential.finditer(text)):
                raise ValueError('Credential assignment needs review: ' + str(path.relative_to(root)))
    for filename in ['shadow', 'gshadow']:
        path = root / 'etc' / filename
        if path.exists() and any(line.split(':')[1] != '!' for line in path.read_text().splitlines()):
            raise ValueError('Account password remained')
    clean = work / 'arch-rootfs.erofs'
    run(['mkfs.erofs', '-zlz4hc,level=9', '-C4096', '-x-1', str(clean), str(root)])
    run(['fsck.erofs', str(clean)])
    rootfs_sha = digest(clean)
    shutil.copyfile(clean, source)
    for path in ['root', 'home', 'data', 'metadata', 'cache']:
        remove(mount, path)
    remove_keys(mount)
    write(mount, 'system/etc/arch/persist.uuid', placeholder + '\n')
    # Compile the same init and launcher entry that later clone builds use.
    binary = work / 'native_init'
    run(['aarch64-linux-gnu-gcc', '-O2', '-static', '-Wall', '-Wextra', '-o', str(binary), str(repo / 'arch/minit_kde.c')])
    for relative in ['native_init', 'system/bin/init']:
        target = owned(mount, relative)
        shutil.copyfile(binary, target)
        target.chmod(0o755)
    launcher = owned(mount, 'system/etc/arch/kde-start.sh')
    shutil.copyfile(repo / 'arch/kde-start.sh', launcher)
    launcher.chmod(0o755)
    run(['sync'])
finally:
    run(['umount', str(mount)])
run(['e2fsck', '-fy', str(image)], allowed=(0, 1))
features = subprocess.check_output(['dumpe2fs', '-h', str(image)], stderr=subprocess.DEVNULL).decode()
had_journal = bool(re.search(r'^Filesystem features:.*\bhas_journal\b', features, re.M))
if had_journal:
    run(['tune2fs', '-O', '^has_journal', str(image)])
    run(['e2fsck', '-fy', str(image)], allowed=(0, 1))
run(['zerofree', str(image)])
if had_journal:
    run(['tune2fs', '-j', str(image)])
run(['e2fsck', '-fn', str(image)])
record = {'schema': 1, 'rootfs_sha256': rootfs_sha, 'persist_uuid': placeholder,
          'image_sha256': digest(image), 'image_bytes': image.stat().st_size,
          'sanitization': stats, 'free_blocks_zeroed': True, 'journal_recreated': had_journal,
          'personal_login_material_removed': True, 'device_tested': False}
(repo / 'out/arch-base-record.json').write_text(json.dumps(record, indent=2) + '\n')
assert work.resolve().parent == (repo / 'out').resolve()
shutil.rmtree(work)
print('ARCH_PUBLIC_BASE_PREPARED', json.dumps(record), flush=True)

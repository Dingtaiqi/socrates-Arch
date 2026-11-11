#!/usr/bin/env python3
"""Start socrates stock-kernel WLAN inside the persistent Arch DSU chroot.

Uses matching vendor/system libraries and firmware from Android slot a, read-only.
No credentials or factory data are copied.
"""
import fcntl
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import time


HOST = Path('/proc/1/root')
LIVE = Path('/dev/kde_dsu/wifi-live')
NODES = Path('/dev/kde_dsu/wifi-block')
SYSTEM = Path('/dev/kde_dsu/stock-system')


def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=20, **kwargs)


def node(source, target, kind):
    major, minor = map(int, (source / 'dev').read_text().strip().split(':'))
    device = os.makedev(major, minor)
    if not target.exists():
        os.mknod(target, kind | 0o600, device)
    info = target.stat()
    if stat.S_IFMT(info.st_mode) != kind or info.st_rdev != device:
        raise RuntimeError(f'Unexpected device node: {target}')
    return f'{major}:{minor}'


def partition(name):
    for path in Path('/sys/class/block').iterdir():
        uevent = path / 'uevent'
        dm = path / 'dm/name'
        if (uevent.exists() and f'PARTNAME={name}' in uevent.read_text().splitlines()) or (
                dm.exists() and dm.read_text().strip() == name):
            return path
    raise RuntimeError(f'Required stock partition absent: {name}')


def mount_ro(name, target, initial_path, filesystem, options):
    source = partition(name)
    block = NODES / name
    device = node(source, block, stat.S_IFBLK)
    target.mkdir(parents=True, exist_ok=True)
    # Read the initial root's mount table: Arch absolute paths differ after chroot.
    for line in Path('/proc/1/mountinfo').read_text().splitlines():
        fields = line.split()
        if fields[4] == initial_path:
            if fields[2] != device or 'ro' not in fields[5].split(','):
                raise RuntimeError(f'Refusing unexpected/writable mount: {initial_path}')
            if fields[fields.index('-') + 1] != filesystem:
                raise RuntimeError(f'Unexpected filesystem: {initial_path}')
            return
    run(['mount', '--no-canonicalize', '-t', filesystem, '-o', options, str(block), str(target)])
    mount_ro(name, target, initial_path, filesystem, options)


def alias(target, source):
    if target.is_symlink():
        if os.readlink(target) != str(source):
            raise RuntimeError(f'Conflicting firmware alias: {target}')
    elif target.exists():
        raise RuntimeError(f'Refusing to replace firmware: {target}')
    else:
        target.symlink_to(source)


def running(program):
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            if os.fsencode(program) in path.read_bytes().split(b'\0'):
                return True
        except OSError:
            pass
    return False


def daemon(name, args, env):
    if running(args[1] if name in ('qrtr-ns', 'cnss-daemon') else args[0]):
        return
    with (LIVE / f'{name}.log').open('ab') as log:
        process = subprocess.Popen(args, env=env, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True, close_fds=True)
    (LIVE / f'{name}.pid').write_text(f'{process.pid}\n')
    time.sleep(1)
    if process.poll() is not None:
        raise RuntimeError(f'{name} exited; see {LIVE}/{name}.log')


def ensure_bus(env):
    Path('/run/dbus').mkdir(parents=True, exist_ok=True)
    address = Path('/run/dbus/system_bus_socket')
    try:
        with socket.socket(socket.AF_UNIX) as bus:
            bus.settimeout(3)
            bus.connect(str(address))
        return
    except (FileNotFoundError, ConnectionRefusedError):
        # /run currently lives in the persistent overlay, including stale sockets.
        if address.exists():
            if not stat.S_ISSOCK(address.stat().st_mode):
                raise RuntimeError('Refusing to replace a non-socket system bus path')
            address.unlink()
    with (LIVE / 'dbus-system.log').open('ab') as log:
        run(['/usr/bin/dbus-daemon', '--system', '--fork', '--nopidfile'],
            env=env, stdout=log, stderr=subprocess.STDOUT)


def main():
    if os.geteuid() != 0 or not Path('/etc/arch-release').exists():
        raise RuntimeError('Run as root inside the Arch DSU')
    if not re.search(r'^androidboot.slot_suffix\s*=\s*"_a"$',
                     Path('/proc/bootconfig').read_text(), re.M):
        raise RuntimeError('Only Android slot a is supported')
    if not os.uname().release.startswith('5.15.194-android13-'):
        raise RuntimeError('This runtime requires the tested stock Android kernel')
    if not Path('/sys/module/kiwi_v2').exists():
        raise RuntimeError('The stock kiwi_v2 module must already be loaded')
    LIVE.mkdir(parents=True, exist_ok=True)
    NODES.mkdir(parents=True, exist_ok=True)
    lock = (LIVE / 'start.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    native = dict(os.environ)
    for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'DBUS_SYSTEM_BUS_ADDRESS', 'DBUS_SESSION_BUS_ADDRESS'):
        native.pop(key, None)
    ensure_bus(native)
    mount_ro('modem_a', HOST / 'vendor/firmware_mnt', '/vendor/firmware_mnt',
             'vfat', 'ro,nosuid,nodev,noexec')
    mount_ro('persist', HOST / 'mnt/vendor/persist', '/mnt/vendor/persist',
             'ext4', 'ro,noload,nosuid,nodev,noexec')
    mount_ro('system_a', SYSTEM, '/mnt' + str(SYSTEM), 'erofs', 'ro,nosuid,nodev')

    hub = Path('/opt/fw')
    if not hub.is_dir():
        raise RuntimeError('GPU firmware directory is missing')
    image = HOST / 'vendor/firmware_mnt/image'
    if not (image / 'kiwi/amss20.bin').is_file():
        raise RuntimeError('Expected kiwi firmware not found')
    for name in ('kiwi', 'kiwi_v2'):
        alias(hub / name, image / 'kiwi')
    alias(hub / 'wlan', HOST / 'vendor/firmware/wlan')
    for file in image.glob('ipa_fws.*'):
        alias(hub / file.name, file)
    for name in ('regulatory.db', 'regulatory.db.p7s'):
        if (Path('/usr/lib/firmware') / name).is_file():
            alias(hub / name, HOST / 'mnt/usr/lib/firmware' / name)
    # The kernel resolves this path against its initial root, not Arch's root.
    Path('/sys/module/firmware_class/parameters/path').write_text('/mnt/opt/fw\n')
    node(Path('/sys/class/wlan/wlan'), Path('/dev/wlan'), stat.S_IFCHR)
    if Path('/sys/class/misc/rfkill/dev').exists():
        node(Path('/sys/class/misc/rfkill'), Path('/dev/rfkill'), stat.S_IFCHR)
    for name in ('/data/vendor/wifi', '/data/vendor/wifi/sockets', '/data/vendor/wlan_logs'):
        Path(name).mkdir(parents=True, exist_ok=True, mode=0o700)

    runtime = Path('/opt/kde-dsu/touch-runtime')
    vendor = dict(native, LD_LIBRARY_PATH=f'{runtime}/lib:{HOST}/vendor/lib64:{SYSTEM}/system/lib64:{SYSTEM}/system/lib64/bootstrap')
    for name, option in (('qrtr-ns', '-f'), ('cnss-daemon', '-n')):
        daemon(name, [str(runtime / 'linker64'), str(HOST / 'vendor/bin' / name), option], vendor)
    if not Path('/sys/class/net/wlan0').exists():
        Path('/sys/kernel/cnss/fs_ready').write_text('1\n')
        for _ in range(30):
            if Path('/sys/class/net/wlan0').exists():
                break
            time.sleep(1)
        else:
            raise RuntimeError('CNSS calibration did not create wlan0 within 30 seconds')

    config = Path('/etc/NetworkManager/conf.d/90-kde-dsu.conf')
    config.parent.mkdir(parents=True, exist_ok=True)
    Path('/var/lib/NetworkManager').mkdir(parents=True, exist_ok=True)
    if not config.exists():
        config.write_text('[main]\ndns=default\nrc-manager=file\n'
                          '[device]\nwifi.backend=wpa_supplicant\n'
                          '[keyfile]\nunmanaged-devices=interface-name:usb0\n')
    daemon('wpa_supplicant', ['/usr/bin/wpa_supplicant', '-u', '-O', '/run/wpa_supplicant'], native)
    daemon('NetworkManager', ['/usr/bin/NetworkManager', '--no-daemon', '--debug', '--log-level=INFO'], native)
    for _ in range(15):
        result = subprocess.run(['nmcli', '-t', '-f', 'RUNNING', 'general'], env=native,
                                capture_output=True, text=True, timeout=5)
        if result.returncode == 0 and result.stdout.strip() == 'running':
            break
        time.sleep(1)
    else:
        raise RuntimeError('NetworkManager did not become ready')
    run(['nmcli', 'radio', 'wifi', 'on'], env=native)
    run(['nmcli', '-f', 'GENERAL.STATE', 'device', 'show', 'wlan0'], env=native)
    print('DSU Wi-Fi runtime ready; saved NetworkManager profiles reconnect automatically.', flush=True)


if __name__ == '__main__':
    main()

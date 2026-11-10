import struct, hashlib, os

SRC = r'D:\zzzzzzzz\_work\vendor_boot_now.img'
OUT = r'D:\zzzzzzzz\_work\bootbak\vendor_boot_a.perm_b20.img'

d = bytearray(open(SRC, 'rb').read())
assert d[:8] == b'VNDRBOOT'
cmd = bytes(d[28:28+2048]).split(b'\x00')[0]
print('orig len', len(cmd))
print('tail:', cmd[-120:].decode(errors='replace'))

if b'androidboot.selinux' in cmd:
    print('already has androidboot.selinux')
else:
    new = cmd + b' androidboot.selinux=permissive'
    assert len(new) < 2048
    d[28:28+2048] = new + b'\x00' * (2048 - len(new))
    open(OUT, 'wb').write(d)
    print('wrote', OUT)
    print('new tail:', new[-160:].decode(errors='replace'))
    print('md5:', hashlib.md5(d).hexdigest())

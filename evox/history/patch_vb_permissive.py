import struct, io

SRC = r'D:\zzzzzzzz\_work\bootbak\vendor_boot_a.img'
OUT = r'D:\zzzzzzzz\_work\bootbak\vendor_boot_a.permtest.img'

d = bytearray(open(SRC, 'rb').read())
assert d[:8] == b'VNDRBOOT', d[:8]
hv = struct.unpack('<I', d[8:12])[0]
cmd = bytes(d[28:28+2048]).split(b'\x00')[0]
print('header_version', hv)
print('orig cmdline:', cmd.decode(errors='replace')[:200])

adds = b' androidboot.selinux=permissive'
if b'androidboot.selinux=' in cmd:
    print('already has selinux param')
else:
    new = cmd + adds
    assert len(new) < 2048
    d[28:28+2048] = new + b'\x00' * (2048 - len(new))
    open(OUT, 'wb').write(d)
    print('wrote', OUT)
    print('new cmdline tail:', new[-160:].decode(errors='replace'))

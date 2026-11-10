import struct

P = r'D:\zzzzzzzz\_work\bootbak\boot_a.orig.img'
OUT = r'D:\zzzzzzzz\_work\bootbak\boot_a.panic10.img'
d = bytearray(open(P, 'rb').read())
assert d[:8] == b'ANDROID!'
(kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr,
 tags_addr, page_size, header_version, os_version) = struct.unpack('<10I', d[8:48])
print('kernel_size=%d ramdisk_size=%d second_size=%d page_size=%d header_version=%d' %
      (kernel_size, ramdisk_size, second_size, page_size, header_version))
name = bytes(d[48:64]).split(b'\x00')[0]
cmdline = bytes(d[64:64+512]).split(b'\x00')[0]
extra = bytes(d[584:584+1024]).split(b'\x00')[0]
print('name:', name)
print('cmdline512 (%d):' % len(cmdline), cmdline[:400])
print('extra1024 (%d):' % len(extra), extra[:400])

# append panic=10 to extra_cmdline if room
add = b' panic=10'
new_extra = extra + add
if len(new_extra) > 1023:
    print('extra too long, fallback to cmdline')
    new_cmd = cmdline + add
    if len(new_cmd) > 511:
        raise SystemExit('cmdline too long')
    d[64:64+512] = new_cmd + b'\x00' * (512 - len(new_cmd))
else:
    d[584:584+1024] = new_extra + b'\x00' * (1024 - len(new_extra))
open(OUT, 'wb').write(d)
print('written', OUT)
print('new extra:', new_extra[:300])

import sys
import io
import os

mnt = sys.argv[1]

p = mnt + '/system/etc/init/cameraserver.rc'
s = io.open(p, encoding='utf-8').read()
if '    disabled\n' not in s:
    s = s.replace('    class main\n', '    class main\n    disabled\n', 1)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
    print('added disabled to cameraserver.rc')
else:
    print('disabled already present')

q = mnt + '/system/etc/init/zzz_camera_delayed.rc'
io.open(q, 'w', encoding='utf-8', newline='\n').write(
    '# [dsu-cam] b57: cameraserver delayed start after boot_completed.\n'
    '# Avoids deadlock: system_server WMS.initPolicy -> PhoneWindowManager.getRearFlashCameraId\n'
    '# -> CameraManager.getCameraIdList waits on cameraserver, while cameraserver waits on activity.\n'
    'on property:sys.boot_completed=1\n'
    '    start cameraserver\n')
print('wrote zzz_camera_delayed.rc')

os.chmod(q, 0o644)
for path, label in ((q, 'u:object_r:system_file:s0'), (p, 'u:object_r:system_file:s0')):
    try:
        os.setxattr(path, 'security.selinux', label.encode() + b'\x00')
    except OSError as e:
        print('setxattr failed', path, e)

print('--- cameraserver.rc ---')
print(io.open(p, encoding='utf-8').read())
print('--- zzz_camera_delayed.rc ---')
print(io.open(q, encoding='utf-8').read())

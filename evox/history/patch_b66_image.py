#!/usr/bin/env python3
# b66 修正：
#  1) 把 EvoX 开机动画放进 /system/media/bootanimation.zip（当前镜像三处都没有 → bootanimation 播内置 fallback "android 加载"动画）
#  2) 移除相机 App（camera HAL 不可用，避免崩溃/误触；禁用数据分区会在重装 DSU 后失效，所以镜像级删除）
#  3) uicap v17：结束时关 stayon(false)，并关闭锁屏（locksettings set-disabled true / secure lockscreen.disabled 1）
import io, os, shutil, subprocess, sys

FW = '/build/evox/out/target/product/socrates/product/media/bootanimation.zip'
MNT = '/mnt/b66'

print('== 1) bootanimation ==')
dst = MNT + '/system/media'
os.makedirs(dst, exist_ok=True)
shutil.copyfile(FW, dst + '/bootanimation.zip')
os.chmod(dst + '/bootanimation.zip', 0o644)
print('bootanimation.zip', os.path.getsize(dst + '/bootanimation.zip'))

print('== 2) 移除相机 App ==')
for p in [
    MNT + '/system/evox_product/app/Aperture',
    MNT + '/system/etc/default-permissions/dsu-aperture.xml',
]:
    if os.path.isdir(p):
        shutil.rmtree(p)
        print('removed dir', p)
    elif os.path.exists(p):
        os.remove(p)
        print('removed', p)
    else:
        print('absent', p)

print('== 3) uicap v17 ==')
p = MNT + '/system/bin/dsu_uicap.sh'
s = io.open(p, encoding='utf-8', errors='replace').read()
if 'dsu_uicap_v17' not in s:
    # 结尾处加锁屏关闭 + stayon off
    add = '''
# [dsu_uicap_v17] 关闭锁屏（DSU 无安全锁，避免开机卡锁屏）并放开常亮
locksettings set-disabled true 2>/dev/null
settings put secure lockscreen.disabled 1 2>/dev/null
svc power stayon false 2>/dev/null
# [/dsu_uicap_v17]
'''
    s = s.rstrip() + '\n' + add
    io.open(p, 'w', encoding='utf-8').write(s)
    print('uicap patched')
else:
    print('already v17')
print('uicap size', os.path.getsize(p))

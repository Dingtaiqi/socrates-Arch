#!/usr/bin/env python3
# b58: cameraserver UidPolicy 死锁修复
# 背景（b55 现场 + 源码）：
#   CameraService::onFirstRef() 里 UidPolicy::registerSelf()/onServiceRegistration()
#   -> registerWithActivityManager() -> ActivityManager::getService()
#   在 binder thread pool 尚未 startThreadPool() 时会 25ms 轮询 checkService("activity")
#   最长 1000s（ActivityManager.cpp）。此时 cameraserver 主线程被卡在 onFirstRef 里，
#   而 system_server 的 WMS.initPolicy -> PhoneWindowManager.getRearFlashCameraId()
#   -> CameraManager.getCameraIdList() 又在同步等 cameraserver -> 三方死锁，Watchdog 反复杀系统。
# 修复：thread pool 未启动时跳过 ActivityManager 注册（只影响 UID 状态观察策略，不影响相机功能）。
p = '/build/evox/frameworks/av/services/camera/libcameraservice/CameraService.cpp'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_cam_deadlock]' in s:
    print('already patched')
    raise SystemExit(0)

# 1) 确保包含 ProcessState
if '#include <binder/ProcessState.h>' not in s:
    old_inc = '#include <binder/IPCThreadState.h>'
    assert old_inc in s
    s = s.replace(old_inc, '#include <binder/IPCThreadState.h>\n#include <binder/ProcessState.h>', 1)
    print('added ProcessState include')

# 2) 在 registerWithActivityManager 开头加保护
anchor = '''void CameraService::UidPolicy::registerWithActivityManager() {
    Mutex::Autolock _l(mUidLock);'''
guard = '''void CameraService::UidPolicy::registerWithActivityManager() {
    // [dsu_cam_deadlock] binder 线程池未启动时，ActivityManager::getService() 会 25ms 轮询
    // checkService("activity")，把 cameraserver 主线程卡在 onFirstRef() 里，
    // 与 system_server 的闪光灯相机查询形成死锁（DSU bring-up 实测）。这里直接跳过注册；
    // UID 观察策略只是相机使用限制优化，缺失不影响相机功能。
    if (!android::ProcessState::self()->isThreadPoolStarted()) {
        ALOGI("UidPolicy: thread pool not started, skip ActivityManager registration "
              "[dsu_cam_deadlock]");
        return;
    }
    Mutex::Autolock _l(mUidLock);'''
assert anchor in s
s = s.replace(anchor, guard, 1)

open(p, 'w', encoding='utf-8').write(s)
print('CameraService.cpp patched [dsu_cam_deadlock]')

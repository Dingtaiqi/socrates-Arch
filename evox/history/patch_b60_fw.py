#!/usr/bin/env python3
# b60: framework 补丁 —— DSU 运行时跳过 WMS.initPolicy 里的相机预解析与 torch/availability 回调注册，
# 消除"system_server 等相机服务、cameraserver 等 activity"的循环死锁。
# 只影响手电筒；相机 App 走独立 Camera2 路径。
p = '/build/evox/frameworks/base/services/core/java/com/android/server/policy/PhoneWindowManager.java'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_port_flash]' in s:
    print('already patched')
    raise SystemExit(0)

# 1) 字段
old_field = '    private boolean mTorchEnabled;'
assert old_field in s
s = s.replace(old_field, old_field + '\n    private boolean mIsDsuRunning;  // [dsu_port_flash]', 1)

# 2) init() 里的 Lineage camera 初始化
old = '''        // Lineage additions
        mAlarmManager = mContext.getSystemService(AlarmManager.class);
        mCameraManager = (CameraManager) mContext.getSystemService(Context.CAMERA_SERVICE);
        try {
            // Resolve the torch camera id up front so TorchModeCallback tracks torch
            // state changes made elsewhere (e.g. QS tile) before the first toggleTorch().
            getRearFlashCameraId();
        } catch (CameraAccessException e) {
            Slog.w(TAG, "Unable to resolve rear flash camera id", e);
        }
        mCameraManager.registerTorchCallback(new TorchModeCallback(), mHandler);
        mCameraAvailabilityListener = new CameraAvailbilityListener();
        mCameraManager.registerAvailabilityCallback(mCameraAvailabilityListener, mHandler);'''
new = '''        // Lineage additions
        mAlarmManager = mContext.getSystemService(AlarmManager.class);
        mCameraManager = (CameraManager) mContext.getSystemService(Context.CAMERA_SERVICE);
        mCameraAvailabilityListener = new CameraAvailbilityListener();
        // [dsu_port_flash] DSU(GSI) bring-up: DSU 里 cameraserver 的注册/启动时序不可靠，
        // 这里开机阶段同步查询相机会让 system_server(WMS.initPolicy) 与 cameraserver 互相等待，
        // 导致 boot_completed 永不置位（实测 Watchdog 反复杀 system_server）。
        // DSU 运行时跳过预解析与 torch/availability 回调注册，只损失手电筒功能。
        mIsDsuRunning = SystemProperties.getInt("ro.gsid.image_running", 0) == 1;
        if (!mIsDsuRunning) {
            try {
                // Resolve the torch camera id up front so TorchModeCallback tracks torch
                // state changes made elsewhere (e.g. QS tile) before the first toggleTorch().
                getRearFlashCameraId();
            } catch (CameraAccessException e) {
                Slog.w(TAG, "Unable to resolve rear flash camera id", e);
            }
            mCameraManager.registerTorchCallback(new TorchModeCallback(), mHandler);
            mCameraManager.registerAvailabilityCallback(mCameraAvailabilityListener, mHandler);
        } else {
            Slog.w(TAG, "[dsu_port_flash] DSU running: skip eager camera query and torch callbacks");
        }'''
assert old in s, 'init block not found'
s = s.replace(old, new, 1)

# 3) toggleTorch 在 DSU 下直接返回
old_t = '''    private void toggleTorch() {
        cancelTorchOff();'''
new_t = '''    private void toggleTorch() {
        // [dsu_port_flash] DSU 下相机服务可能未完全就绪，避免 system_server 卡在 binder 查询
        if (mIsDsuRunning) return;
        cancelTorchOff();'''
assert old_t in s
s = s.replace(old_t, new_t, 1)

open(p, 'w', encoding='utf-8').write(s)
print('PhoneWindowManager.java patched [dsu_port_flash]')

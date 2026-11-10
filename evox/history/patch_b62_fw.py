#!/usr/bin/env python3
# b62: framework 补丁 flash3 —— 一次性盖住 system_server 侧其余会在启动期调 CameraManager 的路径：
#   1) BiometricCameraManagerImpl.<init> 的 registerAvailabilityCallback + isAnyCameraUnavailable 的 getCameraIdList
#   2) CameraStateMonitor.startListeningToCameraState 的 registerAvailabilityCallback
#   3) FlashNotificationsController.prepareForCameraFlashNotification 的 registerTorchCallback/getCameraIdList
# 依据 b61 现场：BiometricService.<init> → BiometricCameraManagerImpl.<init> → ... → getConcurrentCameraIds 阻塞。
import io

ROOT = '/build/evox/frameworks/base/services'

# ---------- 1) BiometricCameraManagerImpl ----------
p1 = ROOT + '/core/java/com/android/server/biometrics/BiometricCameraManagerImpl.java'
s = io.open(p1, encoding='utf-8').read()
if '[dsu_port_flash3]' not in s:
    anchor = 'public class BiometricCameraManagerImpl implements BiometricCameraManager {\n'
    assert anchor in s
    s = s.replace(anchor, anchor + '''
    // [dsu_port_flash3] DSU: 启动期跳过 camera 可用性注册，避免 system_server 卡在 cameraserver
    private static final boolean IS_DSU =
            android.os.SystemProperties.getInt("ro.gsid.image_running", 0) == 1;
''', 1)
    old = '        mCameraManager.registerAvailabilityCallback(mCameraAvailabilityCallback, null);'
    assert old in s
    s = s.replace(old, '''        if (!IS_DSU) {
            mCameraManager.registerAvailabilityCallback(mCameraAvailabilityCallback, null);
        } else {
            android.util.Log.w(TAG, "[dsu_port_flash3] DSU: skip camera availability registration");
        }''', 1)
    old2 = '''    public boolean isAnyCameraUnavailable() {
        try {'''
    assert old2 in s
    s = s.replace(old2, '''    public boolean isAnyCameraUnavailable() {
        if (IS_DSU) return false;  // [dsu_port_flash3] DSU: 不做 camera 查询
        try {''', 1)
    io.open(p1, 'w', encoding='utf-8').write(s)
    print('patched BiometricCameraManagerImpl')
else:
    print('BiometricCameraManagerImpl already patched')

# ---------- 2) CameraStateMonitor ----------
p2 = ROOT + '/core/java/com/android/server/wm/CameraStateMonitor.java'
s = io.open(p2, encoding='utf-8').read()
if '[dsu_port_flash3]' not in s:
    anchor2 = '    private static final String TAG = TAG_WITH_CLASS_NAME ? "CameraStateMonitor" : TAG_WM;'
    assert anchor2 in s
    s = s.replace(anchor2, anchor2 + '''
    // [dsu_port_flash3] DSU: 跳过 camera 可用性注册（启动期会阻塞 system_server）
    private static final boolean IS_DSU =
            android.os.SystemProperties.getInt("ro.gsid.image_running", 0) == 1;''', 1)
    old3 = '''    void startListeningToCameraState() {
        if (mCameraManager != null) {
            mCameraManager.registerAvailabilityCallback(
                    mWmService.mContext.getMainExecutor(), mAvailabilityCallback);
        }
        mIsListeningToCameraState = true;
    }'''
    assert old3 in s
    s = s.replace(old3, '''    void startListeningToCameraState() {
        if (!IS_DSU && mCameraManager != null) {
            mCameraManager.registerAvailabilityCallback(
                    mWmService.mContext.getMainExecutor(), mAvailabilityCallback);
        } else if (IS_DSU) {
            Slog.w(TAG, "[dsu_port_flash3] DSU: skip WM camera availability registration");
        }
        mIsListeningToCameraState = true;
    }''', 1)
    io.open(p2, 'w', encoding='utf-8').write(s)
    print('patched CameraStateMonitor')
else:
    print('CameraStateMonitor already patched')

# ---------- 3) FlashNotificationsController ----------
p3 = ROOT + '/accessibility/java/com/android/server/accessibility/FlashNotificationsController.java'
s = io.open(p3, encoding='utf-8').read()
if '[dsu_port_flash3]' not in s:
    idx = s.find('class FlashNotificationsController')
    assert idx > 0
    brace = s.find('{', idx) + 1
    s = s[:brace] + '''
    // [dsu_port_flash3] DSU: 跳过 camera torch 注册（启动/无障碍路径避免卡 system_server）
    private static final boolean IS_DSU =
            android.os.SystemProperties.getInt("ro.gsid.image_running", 0) == 1;
''' + s[brace:]
    old4 = '''    private void prepareForCameraFlashNotification() {
        mCameraManager = mContext.getSystemService(CameraManager.class);
'''
    assert old4 in s
    s = s.replace(old4, '''    private void prepareForCameraFlashNotification() {
        mCameraManager = mContext.getSystemService(CameraManager.class);
        if (IS_DSU) {
            Log.w(LOG_TAG, "[dsu_port_flash3] DSU: skip camera torch registration for flash notifications");
            return;
        }
''', 1)
    io.open(p3, 'w', encoding='utf-8').write(s)
    print('patched FlashNotificationsController')
else:
    print('FlashNotificationsController already patched')

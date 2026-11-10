#!/usr/bin/env python3
# b61: framework 补丁 2 —— DSU 下跳过 LineageParts device key handler 实例化
# （config_deviceKeyHandlerClasses 里的 org.lineageos.lineageparts.gestures.KeyHandler 构造时会
#   CameraManager.registerTorchCallback → 在 DSU 里同样会卡死 system_server）
p = '/build/evox/frameworks/base/services/core/java/com/android/server/policy/PhoneWindowManager.java'
s = open(p, encoding='utf-8', errors='replace').read()

if '[dsu_port_flash2]' in s:
    print('already patched')
    raise SystemExit(0)

old = '''        for (int i = 0;
                i < deviceKeyHandlerLibs.length && i < deviceKeyHandlerClasses.length; i++) {
            try {
                PathClassLoader loader = new PathClassLoader(
                        deviceKeyHandlerLibs[i], getClass().getClassLoader());
                Class<?> klass = loader.loadClass(deviceKeyHandlerClasses[i]);
                Constructor<?> constructor = klass.getConstructor(Context.class);
                mDeviceKeyHandlers.add((DeviceKeyHandler) constructor.newInstance(mContext));
            } catch (Exception e) {
                Slog.w(TAG, "Could not instantiate device key handler "
                        + deviceKeyHandlerLibs[i] + " from class "
                        + deviceKeyHandlerClasses[i], e);
            }
        }'''
new = '''        // [dsu_port_flash2] DSU(GSI) 下跳过 LineageParts 的 DeviceKeyHandler 实例化：
        // 其中 org.lineageos.lineageparts.gestures.KeyHandler 构造函数会调用
        // CameraManager.registerTorchCallback()，在 DSU 里会阻塞 system_server 启动（实测）。
        // 代价：侧键手势等 LineageParts 按键增强在 DSU 下不可用。
        if (!mIsDsuRunning) {
            for (int i = 0;
                    i < deviceKeyHandlerLibs.length && i < deviceKeyHandlerClasses.length; i++) {
                try {
                    PathClassLoader loader = new PathClassLoader(
                            deviceKeyHandlerLibs[i], getClass().getClassLoader());
                    Class<?> klass = loader.loadClass(deviceKeyHandlerClasses[i]);
                    Constructor<?> constructor = klass.getConstructor(Context.class);
                    mDeviceKeyHandlers.add((DeviceKeyHandler) constructor.newInstance(mContext));
                } catch (Exception e) {
                    Slog.w(TAG, "Could not instantiate device key handler "
                            + deviceKeyHandlerLibs[i] + " from class "
                            + deviceKeyHandlerClasses[i], e);
                }
            }
        } else {
            Slog.w(TAG, "[dsu_port_flash2] DSU running: skip LineageParts device key handlers "
                    + "(KeyHandler registers torch callback)");
        }'''
assert old in s, 'device key handler loop not found'
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print('PhoneWindowManager.java patch2 applied [dsu_port_flash2]')

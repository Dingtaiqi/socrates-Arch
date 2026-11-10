#!/usr/bin/env python3
# 在 SystemServer 里给 DSU 环境加一个开关：跳过 AudioService 初始化。
# 原因（有日志证据）：DSU 下 audioserver 起不来（MIUI vendor 只有 HIDL audio HAL，
# A17 需要 AIDL），AudioService 构造里 AudioSystem.setLowRamDevice 原生调用阻塞 65s，
# 被 framework Watchdog 判定 main thread blocked 并杀掉 system_server，boot_completed 永远不置 1。
p = '/build/evox/frameworks/base/services/java/com/android/server/SystemServer.java'
s = open(p, encoding='utf-8', errors='replace').read()
old = '''            t.traceBegin("StartAudioService");
            if (!isArc) {
                mSystemServiceManager.startService(AudioService.Lifecycle.class);
            } else {'''
new = '''            t.traceBegin("StartAudioService");
            if (!isArc) {
                // [dsu-port] DSU：宿主 vendor 只有 HIDL 音频 HAL，A17 audioserver 起不来，
                // AudioService 构造会在 AudioSystem.setLowRamDevice 阻塞 60s+，被 framework
                // Watchdog 杀掉 system_server，导致永远到不了 boot_completed。
                // 这里在 DSU 环境下跳过 AudioService（persist.dsu.audio.enable=1 可强制开启）。
                final boolean dsuSkipAudio = new java.io.File("/metadata/gsi/dsu/active").exists()
                        && !android.os.SystemProperties.getBoolean("persist.dsu.audio.enable", false);
                if (dsuSkipAudio) {
                    Slog.w(TAG, "[dsu-port] DSU: skip AudioService (incompatible vendor audio HAL)");
                } else {
                    mSystemServiceManager.startService(AudioService.Lifecycle.class);
                }
            } else {'''
if '[dsu-port] DSU: skip AudioService' in s:
    print('already patched')
elif old in s:
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('SystemServer.java patched')
else:
    print('ANCHOR NOT FOUND')

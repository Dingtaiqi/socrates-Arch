#!/system/bin/sh
# [dsu-uicap v10] DSU 启动完成后自动采集：wake/unlock → provisioning → adb key 诊断
# → screencap → WiFi 连接测试 → BT/指纹/camera/display/audio dumps → uicap_done。
# 由 init 在检测到 sys.boot_completed=1 后调用（不依赖 adb）。
P=/mnt/vendor/persist/dsu
mkdir -p $P

# 0) 先唤醒/解锁（必须早于 settings 写 secure；锁屏下 secure 写不进）
input keyevent 224 >/dev/null 2>&1
wm dismiss-keyguard >/dev/null 2>&1
svc power stayon true >/dev/null 2>&1
sleep 2

# 1) provisioning（不置位时 Settings 会报 "Device is not provisioned, exiting Settings"）
settings put global device_provisioned 1 >/dev/null 2>&1
settings put secure user_setup_complete 1 >/dev/null 2>&1

# 2) adb key 诊断
{
  echo "=== adb key diag ==="
  echo "ro.adb.secure=$(getprop ro.adb.secure)"
  echo "ro.debuggable=$(getprop ro.debuggable)"
  echo "init.svc.adbd=$(getprop init.svc.adbd)"
  ls -l /adb_keys /system/etc/adb_keys /data/misc/adb 2>&1
  wc -c /adb_keys /system/etc/adb_keys /data/misc/adb/adb_keys 2>&1
  md5sum /adb_keys /system/etc/adb_keys /data/misc/adb/adb_keys 2>&1
} > $P/adb_key_diag.txt 2>&1

# 3) 截图（screencap 已修复；记录 rc + sync + 字节数）
timeout 15 screencap -p $P/screen.png 2> $P/screencap_0.log
sc_rc=$?
sync
sc_size=$(stat -c %s $P/screen.png 2>/dev/null)
if [ -z "$sc_size" ] || [ "$sc_size" -lt 10000 ] 2>/dev/null; then
  timeout 15 screencap -d 0 -p $P/screen.png 2> $P/screencap_1.log
  sc_rc=$?
  sync
  sc_size=$(stat -c %s $P/screen.png 2>/dev/null)
fi
screen_ok=${sc_size:-0}
echo "screencap_rc=$sc_rc screen_ok=$screen_ok" > $P/screencap_result.txt

# 4) WiFi 连接测试（SSID/密码都是 REDACTED_WIFI_PASS；连接后最多轮询 30s 等 inet）
{
  echo "=== wifi before ==="
  cmd wifi status
  echo "=== enable ==="
  cmd wifi set-wifi-enabled enabled
  sleep 5
  echo "=== scan(VT4009) ==="
  cmd wifi list-scan-results 2>/dev/null | grep -i "VT4009"
  echo "=== connect ==="
  cmd wifi connect-network REDACTED_WIFI_PASS wpa2 REDACTED_WIFI_PASS
  wifi_ok=0
  i=0
  while [ $i -lt 15 ]; do
    sleep 2
    i=$((i+1))
    if ip addr show wlan0 2>/dev/null | grep -q "inet "; then wifi_ok=1; break; fi
  done
  echo "=== status ==="
  cmd wifi status
  echo "=== ip addr wlan0 ==="
  ip addr show wlan0
  echo "=== ip route ==="
  ip route
  echo "=== ping 223.5.5.5 ==="
  ping -c 2 -W 2 223.5.5.5
  echo "wifi_ok=$wifi_ok"
} > $P/wifi_connect.txt 2>&1

# 5) 功能探测归档
{
  echo "=== fingerprint ==="
  timeout 10 dumpsys fingerprint 2>&1 | head -40
  echo "=== bt ==="
  timeout 10 cmd bluetooth_manager enable
  sleep 2
  timeout 10 dumpsys bluetooth_manager 2>&1 | grep -i -E "enabled|state" | head -10
  echo "=== camera ==="
  dumpsys media.camera 2>&1 | head -30
  echo "=== display ==="
  dumpsys display 2>&1 | grep -E "mScreenState|Display State|mState=" | head -10
  echo "=== audio ==="
  dumpsys media.audio_flinger 2>&1 | head -20
} > $P/func_diag.txt 2>&1

# 6) 完成标记
echo "boot=$(getprop sys.boot_completed) adb=$(getprop init.svc.adbd) uicap=2 screen_ok=$screen_ok" > $P/uicap_done

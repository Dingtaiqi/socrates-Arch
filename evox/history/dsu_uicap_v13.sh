#!/system/bin/sh
# [dsu-uicap v13] REDACTED_WIFI_SSID + camera restart 测试（AIDL 注册竞态） = v11 + dsu-compat review 5 处修正
#  - camera_ok 去误报（ps USER 列）+ service list 只抓一次落盘 + camera_aidl=0 自动抓日志
#  - WiFi 参数化（顶部改 SSID/PASS/OPTS）+ 全部套 timeout
#  - display/audio dumpsys 套 timeout、uicap_done 前 sync、加 gsid 字段
# 由 init 在检测到 sys.boot_completed=1 后调用（不依赖 adb）
P=/mnt/vendor/persist/dsu
mkdir -p $P

# ===== 参数区（用户确认 SSID 后只改这里）=====
WIFI_SSID="${DSU_WIFI_SSID:-}"
WIFI_PASS="${DSU_WIFI_PASSWORD:-}"
WIFI_OPTS=""            # 隐藏网络用 "-h"；hex SSID 用 "-x"；指定 BSSID 用 "-b <bssid>"
WIFI_SCAN_FILTER="${DSU_WIFI_SCAN_FILTER:-}"
# =============================================

screen_ok=0
wifi_ok=0
camera_ok=0
camera_aidl=0

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

# 4) WiFi 连接测试（参数在顶部；连接后最多轮询 30s 等 inet）
{
  echo "=== wifi before ==="
  timeout 20 cmd wifi status
  echo "=== enable ==="
  timeout 20 cmd wifi set-wifi-enabled enabled
  sleep 5
  echo "=== start-scan ==="
  timeout 20 cmd wifi start-scan
  sleep 8
  echo "=== scan($WIFI_SCAN_FILTER) ==="
  timeout 20 cmd wifi list-scan-results 2>/dev/null | grep -i "$WIFI_SCAN_FILTER"
  echo "=== scan(all, head 40) ==="
  timeout 20 cmd wifi list-scan-results 2>/dev/null | head -40
  for ssid in "$WIFI_SSID" "REDACTED_WIFI_SCAN_FILTER"; do
    echo "=== connect [$ssid] ==="
    timeout 20 cmd wifi connect-network "$ssid" wpa2 "$WIFI_PASS" $WIFI_OPTS
    i=0
    while [ $i -lt 10 ]; do
      sleep 2
      i=$((i+1))
      if ip addr show wlan0 2>/dev/null | grep -q "inet "; then wifi_ok=1; break 2; fi
    done
  done
  echo "=== status ==="
  timeout 20 cmd wifi status
  echo "=== ip addr wlan0 ==="
  ip addr show wlan0
  echo "=== ip route ==="
  ip route
  echo "=== ping 223.5.5.5 ==="
  ping -c 2 -W 2 223.5.5.5
  echo "wifi_ok=$wifi_ok"
} > $P/wifi_connect.txt 2>&1
echo "wifi_ok=$wifi_ok" > $P/wifi_result.txt

# 5) 功能探测归档（指纹/BT/display/audio；camera 见第 5b 段）
{
  echo "=== fingerprint ==="
  timeout 10 dumpsys fingerprint 2>&1 | head -40
  echo "=== bt ==="
  timeout 10 cmd bluetooth_manager enable
  sleep 2
  timeout 10 dumpsys bluetooth_manager 2>&1 | grep -i -E "enabled|state" | head -10
  echo "=== display ==="
  timeout 10 dumpsys display 2>&1 | grep -E "mScreenState|Display State|mState=" | head -10
  echo "=== audio ==="
  timeout 10 dumpsys media.audio_flinger 2>&1 | head -20
} > $P/func_diag.txt 2>&1

# 5b-0) camera 注册竞态测试：b52 里 cameraserver 被 SIGKILL 后 23ms 就重启，
#       AidlCameraService::registerService 只尝试一次，可能撞 EX_ALREADY_EXISTS 永久丢失服务。
#       这里做一次“干净重启”（stop 后等 3s 让 servicemanager 清理旧 binder），再轮询 AIDL 是否恢复。
{
  echo "=== cameraserver before ==="
  pidof cameraserver 2>&1
  timeout 10 service check android.frameworks.cameraservice.service.ICameraService/default 2>&1
  echo "=== restart cameraserver (clean) ==="
  stop cameraserver 2>&1
  sleep 3
  start cameraserver 2>&1
  i=0
  while [ $i -lt 60 ]; do
    sleep 2
    i=$((i+2))
    if timeout 10 service check android.frameworks.cameraservice.service.ICameraService/default 2>/dev/null | grep -q "found"; then
      echo "AIDL registered after ${i}s"
      break
    fi
  done
  echo "=== cameraserver after ==="
  pidof cameraserver 2>&1
  timeout 10 service check android.frameworks.cameraservice.service.ICameraService/default 2>&1
} > $P/camera_restart.txt 2>&1

# 5b) camera 诊断（A17 只有 AIDL 名；旧 media.camera 不存在；只做注册/进程/二进制核对）
#     service list 只抓一次落盘（顺带解决 b51 被 head 截断的疑点）
timeout 10 service list > $P/service_list_full.txt 2>&1
{
  echo "=== cameraserver restart result ==="
  cat $P/camera_restart.txt
  echo "=== service list (camera) after restart ==="
  grep -iE 'camera' $P/service_list_full.txt
} > $P/camera_after.txt 2>&1
{
  echo "=== service list (camera) ==="
  grep -iE 'camera' $P/service_list_full.txt
  echo "=== service check AIDL ==="
  timeout 10 service check android.frameworks.cameraservice.service.ICameraService/default 2>&1
  echo "=== ps (camera) ==="
  timeout 10 ps -A 2>/dev/null | grep -iE 'camera'
  echo "=== /vendor/bin/hw (camera) ==="
  ls -l /vendor/bin/hw 2>&1 | grep -iE 'camera'
  echo "=== dumpsys -l (camera) ==="
  timeout 10 dumpsys -l 2>&1 | grep -iE 'camera'
  echo "=== getprop (camera) ==="
  getprop 2>/dev/null | grep -iE 'camera'
  echo "=== /dev/video* ==="
  ls -l /dev/video* 2>&1
} > $P/camera_diag.txt 2>&1

# camera_ok：用 pidof（base52 镜像已确认 /system/bin/pidof -> toybox）判定 cameraserver 进程，
# 避免 ps 输出首列是 USER 导致的误判（b52 camera_ok=0 的判定 bug）
if pidof cameraserver >/dev/null 2>&1 && \
   grep -q 'ICameraProvider/vendor_qti' $P/service_list_full.txt; then camera_ok=1; fi
camera_aidl=0
grep -q 'android.frameworks.cameraservice.service.ICameraService/default' $P/service_list_full.txt && camera_aidl=1
echo "camera_ok=$camera_ok camera_aidl=$camera_aidl" >> $P/camera_diag.txt

# camera_aidl=0 时自动抓日志（省一轮采集）
if [ "${camera_aidl:-0}" -eq 0 ]; then
  timeout 20 logcat -b all -d -t 3000 2>/dev/null | grep -iE 'AIDL vndk|cameraserver|ICameraService' > $P/camera_logcat_tail.txt 2>&1
fi

# 6) 完成标记（带 screen_ok / wifi_ok / camera_ok / camera_aidl / prov / gsid）
prov=$(settings get global device_provisioned 2>/dev/null)
gsid=$(getprop ro.gsid.image_running 2>/dev/null)
sync
echo "boot=$(getprop sys.boot_completed) adb=$(getprop init.svc.adbd) uicap=3.2 screen_ok=${screen_ok:-0} wifi_ok=${wifi_ok:-0} camera_ok=${camera_ok:-0} camera_aidl=${camera_aidl:-0} prov=${prov:-?} gsid=${gsid:-?}" > $P/uicap_done

#!/bin/sh
# K60 Pro DSU desktop using the verified 60 Hz / GPU-compositor configuration.
set -eu
[ "$(id -u)" = 0 ]
[ -f /etc/arch-release ]
kit=/opt/kde-dsu
log=/dev/kde_dsu/desktop-$(date +%s)
mkdir -p /run/kde-dsu /run/dbus /tmp /root/.config /root/.local/share/applications "$log" /dev/input /dev/dri /dev/dma_heap
chmod 1777 /tmp
chmod 700 /root /run/kde-dsu
exec 9>/run/kde-dsu/desktop.lock
flock -n 9 || { printf 'A DSU desktop launcher is already running.\n'; exit 1; }
char_node() {
    IFS=: read -r major minor <"$1"
    case "$major:$minor" in *[!0-9:]*|:|*:) return 1;; esac
    if [ -e "$2" ]; then
        [ -c "$2" ]
        [ "$(stat -c '%t:%T' "$2")" = "$(printf '%x:%x' "$major" "$minor")" ]
    else
        mknod -m 600 "$2" c "$major" "$minor"
    fi
}
char_node /sys/class/drm/card0/dev /dev/dri/card0
char_node /sys/class/kgsl/kgsl-3d0/dev /dev/kgsl-3d0
char_node /sys/class/dma_heap/system/dev /dev/dma_heap/system
char_node /sys/class/misc/xiaomi-touch/dev /dev/xiaomi-touch
for sys in /sys/class/input/event*; do char_node "$sys/dev" "/dev/input/${sys##*/}"; done
mkdir -p /run/udev /data/vendor/touch
if ! pgrep -x systemd-udevd >/dev/null; then /usr/lib/systemd/systemd-udevd --daemon; fi
SYSTEMD_IN_CHROOT=0 udevadm trigger --action=add --subsystem-match=input
SYSTEMD_IN_CHROOT=0 udevadm settle --timeout=10
for name in a740_sqe.fw a740_zap.mbn gmu_gen70200.bin; do
    [ -r "/proc/1/root/mnt/opt/fw/$name" ]
done
printf '%s\n' /mnt/opt/fw >/sys/module/firmware_class/parameters/path
for src in "$kit"/profile/*; do
    [ -f "$src" ] || continue
    dest=/root/.config/${src##*/}
    [ -f "$dest" ] || cp "$src" "$dest"
done
[ -s /etc/machine-id ] || dbus-uuidgen >/etc/machine-id
if ! timeout 5 dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.GetId >/dev/null 2>&1; then
    # /run is currently in the persistent overlay; a socket can outlive its daemon.
    rm -f /run/dbus/system_bus_socket
    dbus-daemon --system --fork --nopidfile
fi
if ! timeout 90 python3 /proc/1/root/system/etc/arch/wifi-start.py >"$log/wifi-start.log" 2>&1; then
    printf 'Wi-Fi startup failed; see %s/wifi-start.log\n' "$log"
fi
touch_pid=
logger_pid=
cleanup() {
    [ -z "$touch_pid" ] || kill "$touch_pid" 2>/dev/null || true
    if [ -n "$logger_pid" ]; then kill "$logger_pid" 2>/dev/null || true; rm -f /dev/socket/logdw; fi
    printf '0\n' >/sys/class/backlight/panel0-backlight/brightness
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p /dev/socket
if [ ! -e /dev/socket/logdw ]; then
    python3 -u - >"$log/touch-logd.txt" 2>&1 <<'LOGGER' &
import socket, time
s=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM)
s.bind('/dev/socket/logdw')
count=0; reported=time.monotonic()
while True:
    message=s.recv(65536); count+=1
    if count<=20: print(repr(message),flush=True)
    if time.monotonic()-reported>30:
        print('ANDROID_LOG_MESSAGES',count,flush=True); reported=time.monotonic()
LOGGER
    logger_pid=$!
fi
if ! pgrep -f '^/opt/kde-dsu/touch-runtime/linker64 /opt/kde-dsu/touch-runtime/touch_report$' >/dev/null; then
    env -u LD_PRELOAD LD_LIBRARY_PATH="$kit/touch-runtime/lib" \
        "$kit/touch-runtime/linker64" "$kit/touch-runtime/touch_report" >"$log/touch-report.log" 2>&1 &
    touch_pid=$!
    sleep 2
    kill -0 "$touch_pid"
fi
cat >/root/.local/share/applications/kde-dsu-hyperos.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Return to HyperOS
Name[zh_CN]=重启返回 HyperOS
Exec=/opt/kde-dsu/tools/bin/reboot_system
Icon=system-reboot
Terminal=false
Categories=System;
DESKTOP
cat >"$log/session.sh" <<'SESSION'
#!/bin/sh
set -eu
dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR XDG_MENU_PREFIX HOME
kscreen-doctor -o >"$KDE_PROBE_LOG/outputs.txt" 2>&1
qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >"$KDE_PROBE_LOG/kwin-support.txt" 2>&1
env QT_QUICK_BACKEND=software QSG_INFO=1 plasmashell >"$KDE_PROBE_LOG/plasmashell.log" 2>&1 &
shell_pid=$!
sleep 5
konsole --separate -e sh -c 'printf "K60 Pro KDE / DSU\nAdreno 740 compositor / 60 Hz\n\n"; exec /bin/bash' >"$KDE_PROBE_LOG/konsole.log" 2>&1 &
wait "$shell_pid"
SESSION
chmod 700 "$log/session.sh"
mkdir -p "$log/runtime"
chmod 700 "$log/runtime"
printf '800\n' >/sys/class/backlight/panel0-backlight/brightness
dmesg >"$log/dmesg-before.log"
set +e
env -u HYBRIS_LD_LIBRARY_PATH -u WAYLAND_DISPLAY -u DISPLAY -u LIBGL_ALWAYS_SOFTWARE -u QT_QUICK_BACKEND -u KWIN_COMPOSE \
 LD_LIBRARY_PATH="$kit/tools/lib:$kit/turnip-26.2.6/lib" \
 VK_DRIVER_FILES="$kit/turnip-26.2.6/share/vulkan/icd.d/freedreno_icd.aarch64.json" \
 MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink \
 __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
 SOCRATES_EVENT_TIMESTAMP_FALLBACK=1 SOCRATES_DIAGNOSTIC_CRTC0=1 SOCRATES_DIAGNOSTIC_XRGB8888=1 \
 LD_PRELOAD="$kit/diagnostics/libdrm_plane_xrgb_diagnostic.so:$kit/diagnostics/libdrm_timestamp_diagnostic.so" \
 XDG_RUNTIME_DIR="$log/runtime" HOME=/root KDE_PROBE_LOG="$log" \
 XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland XDG_MENU_PREFIX=plasma- QT_QPA_PLATFORM=wayland LANG=C.UTF-8 \
 KWIN_DRM_DEVICES=/dev/dri/card0 KWIN_USE_OVERLAYS=0 \
 dbus-run-session -- kwin_wayland --drm --no-lockscreen --no-global-shortcuts \
 --no-kactivities --socket=kde-plasma --exit-with-session="$log/session.sh" >"$log/kwin.log" 2>&1
rc=$?
set -e
dmesg >"$log/dmesg-after.log"
printf 'KDE_DESKTOP_EXIT=%s log=%s\n' "$rc" "$log"
exit "$rc"

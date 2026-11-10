set -eu
[ -f /etc/arch-release ]
[ "$(findmnt -n -o FSTYPE /)" = overlay ]
curl -fsS --connect-timeout 3 --max-time 30 http://192.168.137.1:18780/touch-runtime.tar.gz -o /dev/touch-runtime.tar.gz
printf '%s  %s\n' e83008b3e93fd7bb274d3ffef77cba0c2915297b37ec1ab3d510df2caaf34833 /dev/touch-runtime.tar.gz | sha256sum -c -
tar -C /opt/kde-dsu -xzf /dev/touch-runtime.tar.gz
cp /proc/1/root/odm/bin/touch_report /opt/kde-dsu/touch-runtime/touch_report
mkdir -p /odm/firmware /data/vendor/touch
for name in goodix_normalize.csv goodix_normalize_1.csv; do
 [ -f "/proc/1/root/odm/firmware/$name" ] && cp "/proc/1/root/odm/firmware/$name" "/odm/firmware/$name"
done
IFS=: read -r major minor </sys/class/misc/xiaomi-touch/dev
[ -c /dev/xiaomi-touch ] || mknod -m 600 /dev/xiaomi-touch c "$major" "$minor"
printf 'TOUCH FILE HASHES\n'; sha256sum /opt/kde-dsu/touch-runtime/touch_report /odm/firmware/goodix_normalize*.csv
printf 'LINKER HELP\n'
timeout -k 2 5 /opt/kde-dsu/touch-runtime/linker64 --help

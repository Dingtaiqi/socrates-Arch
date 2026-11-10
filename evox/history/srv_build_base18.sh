#!/bin/bash
set -e
P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
# 先看看宿主 init.zygote64_32.rc 是否存在
adb() { :; }
ls /build/evox/out/target/product/socrates/system/etc/init/hw/ 2>/dev/null | grep -i zygote || true

SRC=/build/out/evox_socrates_base17.img
IMG=/build/out/evox_socrates_base18.img
MNT=/mnt/base18
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 1) 恢复策略文件 SELinux 标签（关键！）
python3 - <<"PYEOF"
import os
MNT="/mnt/base18/system/etc/selinux"
labels = {
 "plat_file_contexts": "file_contexts_file",
 "plat_hwservice_contexts": "hwservice_contexts_file",
 "plat_keystore2_key_contexts": "keystore2_key_contexts_file",
 "plat_mac_permissions.xml": "mac_perms_file",
 "plat_property_contexts": "property_contexts_file",
 "plat_seapp_contexts": "seapp_contexts_file",
 "plat_sepolicy.cil": "sepolicy_file",
 "plat_sepolicy_and_mapping.sha256": "system_file",
 "plat_sepolicy_genfs_202504.cil": "system_file",
 "plat_sepolicy_genfs_202604.cil": "system_file",
 "plat_sepolicy_genfs_202704.cil": "system_file",
 "plat_service_contexts": "service_contexts_file",
 "plat_tee_service_contexts": "tee_service_contexts_file",
 "bug_map": "system_file",
 "system_ext_sepolicy.cil": "sepolicy_file",
}
for name, t in labels.items():
    p = os.path.join(MNT, name)
    if os.path.exists(p):
        try:
            os.setxattr(p, "security.selinux", ("u:object_r:%s:s0" % t).encode() + b"\x00")
        except Exception as e:
            print("xattr fail", name, e)
mapdir = os.path.join(MNT, "mapping")
if os.path.isdir(mapdir):
    for f in os.listdir(mapdir):
        p = os.path.join(mapdir, f)
        if os.path.isfile(p):
            t = "sepolicy_file" if f.endswith(".cil") and not f.startswith("202") else "system_file"
            try:
                os.setxattr(p, "security.selinux", ("u:object_r:%s:s0" % t).encode() + b"\x00")
            except Exception as e:
                print("xattr fail", f, e)
for p in [MNT, mapdir]:
    if os.path.isdir(p):
        try:
            os.setxattr(p, "security.selinux", b"u:object_r:system_file:s0\x00")
        except Exception as e:
            print("xattr fail dir", p, e)
print("labels done")
PYEOF

# 2) 补 init.zygote64_32.rc（宿主 vendor 设置 ro.zygote=zygote64_32，镜像只有 zygote64）
cat > $MNT/system/etc/init/hw/init.zygote64_32.rc <<"EOF"
# [dsu-port] 兼容宿主 ro.zygote=zygote64_32：仅起 64 位 zygote
service zygote /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
    class main
    priority -20
    user root
    group root readproc reserved_disk
    socket zygote stream 660 root system
    socket usap_pool_primary stream 660 root system
    onrestart exec_background - system system -- /system/bin/ps -A -o pid,ppid,user,args
    onrestart write /sys/android_power/request_state wake
    onrestart write /sys/power/state on
    onrestart restart audioserver
    onrestart restart cameraserver
    onrestart restart media
    onrestart restart netd
    onrestart restart wificond
    writepid /dev/cpuset/foreground/tasks
    task_profiles ProcessCapacityHigh MaxPerformance

service zygote_secondary /system/bin/app_process32 -Xzygote /system/bin --zygote --socket-name=zygote_secondary --enable-lazy-preload
    class main
    priority -20
    user root
    group root readproc reserved_disk
    socket zygote_secondary stream 660 root system
    onrestart write /sys/android_power/request_state wake
    onrestart write /sys/power/state on
    onrestart restart audioserver
    onrestart restart cameraserver
    onrestart restart media
    onrestart restart netd
    onrestart restart wificond
    writepid /dev/cpuset/foreground/tasks
    task_profiles ProcessCapacityHigh MaxPerformance
EOF
chmod 644 $MNT/system/etc/init/hw/init.zygote64_32.rc
python3 -c "import os; os.setxattr(\"/mnt/base18/system/etc/init/hw/init.zygote64_32.rc\",\"security.selinux\",b\"u:object_r:system_file:s0\x00\")"
echo "zygote rc added"

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
cd /home/qinghuo
sed "s#/build/out/evox_socrates_base2.img#/build/out/evox_socrates_base17.img#" gen_diff3.py > gen_diff18.py
python3 gen_diff18.py /build/out/evox_socrates_base18.img /home/qinghuo/base18.diff
chown qinghuo /home/qinghuo/base18.diff
ls -la /home/qinghuo/base18.diff
'

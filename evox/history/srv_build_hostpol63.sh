P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
BC=$(cat /mnt/filtered_bc.txt)
SS=$(cat /mnt/filtered_ss.txt)

SRC=/build/out/evox_socrates_system_hostpol62.img
IMG=/build/out/evox_socrates_system_hostpol63.img
MNT=/mnt/hp63
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT

# 恢复标准 app_process64 路径
python3 - <<"PYEOF"
import io
for p in ["/mnt/hp63/system/etc/init/hw/init.zygote64.rc",
          "/mnt/hp63/system/etc/init/zzz_dsu_zygote_dbg.rc"]:
    s = io.open(p, encoding="utf-8").read()
    s = s.replace("/system/bin/app_process64x", "/system/bin/app_process64")
    io.open(p, "w", encoding="utf-8").write(s)
    print("fixed", p)
PYEOF
rm -f $MNT/system/bin/app_process64x

# 写入过滤后的 classpath
cat > $MNT/system/etc/init/zzz_dsu_classpath.rc <<EOF
# [dsu-port] 覆盖宿主 ramdisk 带来的 BOOTCLASSPATH（含本镜像不存在的 miui jar）
export BOOTCLASSPATH $BC
export DEX2OATBOOTCLASSPATH $BC
export SYSTEMSERVERCLASSPATH $SS
export ANDROID_ROOT /system
export ANDROID_DATA /data
export ANDROID_ART_ROOT /apex/com.android.art
EOF
head -3 $MNT/system/etc/init/zzz_dsu_classpath.rc | cut -c1-200

sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

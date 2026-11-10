P=${BUILD_SUDO_PASSWORD:?set outside this repository}
echo "$P" | sudo -S -p '' bash -c '
set -e
BC=$(cat /mnt/filtered_bc.txt)
SS=$(cat /mnt/filtered_ss.txt)

SRC=/build/out/evox_socrates_system_hostpol65.img
IMG=/build/out/evox_socrates_system_hostpol66.img
MNT=/mnt/hp66
cp -a $SRC $IMG
umount $MNT 2>/dev/null || true
mkdir -p $MNT
mount -o loop,rw $IMG $MNT
echo "== 镜像根目录 =="
ls $MNT | head -10

# 在镜像根目录创建 init.environ.rc（DSU 下 / = 镜像根）
cat > $MNT/init.environ.rc <<EOF
# [dsu-port] DSU 启动时根目录是 system 镜像（没有 ramdisk 的 init.environ.rc）
export BOOTCLASSPATH $BC
export DEX2OATBOOTCLASSPATH $BC
export SYSTEMSERVERCLASSPATH $SS
export ANDROID_ROOT /system
export ANDROID_DATA /data
export ANDROID_ART_ROOT /apex/com.android.art
EOF
chmod 644 $MNT/init.environ.rc
ls -la $MNT/init.environ.rc
head -2 $MNT/init.environ.rc | cut -c1-160

# classpath rc 也改成 on early-init（双保险）
cat > $MNT/system/etc/init/zzz_dsu_classpath.rc <<EOF
# [dsu-port] 双保险：early-init 里再 export 一次
on early-init
    export BOOTCLASSPATH $BC
    export DEX2OATBOOTCLASSPATH $BC
    export SYSTEMSERVERCLASSPATH $SS
    export ANDROID_ROOT /system
    export ANDROID_DATA /data
    export ANDROID_ART_ROOT /apex/com.android.art
EOF
sync
umount $MNT
e2fsck -f -y $IMG 2>&1 | tail -1
chown qinghuo $IMG
sha256sum $IMG
'

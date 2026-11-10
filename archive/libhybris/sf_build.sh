#!/bin/bash
set -e
cd /root
rm -rf ub-sf
mkdir ub-sf
tar xzf libhybris-7079712.tar.gz -C ub-sf --strip-components=1
cd ub-sf
for p in /root/ubports-hybris-pack/debian/patches/0*.patch; do
  patch -p1 --forward --batch < "$p" >/dev/null 2>&1 || echo "patch-fail $(basename "$p")"
done
echo PATCHES-APPLIED
python3 /root/sf_patch_egl.py hybris/egl/egl.c
cd hybris
./autogen.sh >/tmp/sf_autogen.log 2>&1 || true
PKG_CONFIG_PATH=/root/fakepc ./configure --host=aarch64-linux-gnu --with-android-headers=/root/android-headers-30 \
  --enable-arch=arm64 --enable-property-cache --enable-experimental --enable-mali-quirks --disable-wayland \
  --disable-mesa --prefix=/usr >/tmp/sf_conf.log 2>&1
echo CONF=$?
mkdir -p include
cp /root/wlinc/wayland-egl-backend.h include/ 2>/dev/null || true
for d in common libsync properties hardware ui gralloc platforms/common egl/platforms/common egl/platforms/null egl/platforms/fbdev egl glesv2; do
  make -C "$d" -j4 >/tmp/sf_build_$d.log 2>&1 || { echo "BUILD-FAIL $d"; tail -5 /tmp/sf_build_$d.log; }
done
echo BUILT
echo -n "STRINGS="
strings egl/.libs/libEGL.so.1.0.0 | grep -c "MESA_platform_surfaceless" || true
aarch64-linux-gnu-strip --strip-unneeded egl/.libs/libEGL.so.1.0.0 2>/dev/null || true
cd /root
rm -rf hybsf
mkdir hybsf
cp -L /root/ub-sf/hybris/egl/.libs/libEGL.so.1.0.0 hybsf/
cd hybsf
echo -n "PACK-STRINGS="
strings -a libEGL.so.1.0.0 | grep -c "MESA_platform_surfaceless" || true
ln -sf libEGL.so.1.0.0 libEGL.so.1
ln -sf libEGL.so.1.0.0 libEGL.so
tar czf /root/hybsf.tar.gz .
ls -la /root/hybsf.tar.gz
md5sum libEGL.so.1.0.0

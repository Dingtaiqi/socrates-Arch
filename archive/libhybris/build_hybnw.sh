#!/bin/bash
set -e
cd /root
rm -rf ub-sf2
mkdir ub-sf2
tar xzf libhybris-7079712.tar.gz -C ub-sf2 --strip-components=1
cd ub-sf2
for p in /root/ubports-hybris-pack/debian/patches/0*.patch; do
  patch -p1 --forward --batch < "$p" >/dev/null 2>&1 || echo "patch-fail $(basename "$p")"
done
echo PATCHES-DONE
python3 /root/sf_patch_egl.py hybris/egl/egl.c
cd hybris
chmod +x autogen.sh
./autogen.sh >/tmp/sf2_autogen.log 2>&1
echo AUTOGEN=$?
grep -n "wayland" config.h | head -3 || true
PKG_CONFIG_PATH=/root/fakepc ./configure --host=aarch64-linux-gnu --build=x86_64-linux-gnu \
  --with-android-headers=/root/android-headers-30 --enable-arch=arm64 \
  --enable-property-cache --enable-experimental --enable-mali-quirks \
  --disable-mesa --prefix=/usr >/tmp/sf2_conf.log 2>&1
echo CONF=$?
grep -E "wayland|Wayland" /tmp/sf2_conf.log | tail -5 || true
grep -n "WANT_WAYLAND" config.h || echo "NO-WANT-WAYLAND"
mkdir -p include
cp /root/wlinc/wayland-egl-backend.h include/ 2>/dev/null || true
for d in common platforms/common egl/platforms/common egl/platforms/null egl/platforms/fbdev egl glesv2; do
  log="/tmp/sf2_$(echo "$d" | tr '/' '_').log"
  if make -C "$d" -j4 >"$log" 2>&1; then echo "OK $d"; else echo "FAIL $d"; tail -6 "$log"; fi
done
echo -n "MESA-STR="
strings egl/.libs/libEGL.so.1.0.0 | grep -c "EGL_MESA_platform_surfaceless" || true
echo -n "WAYLAND-EXT-STR="
strings egl/.libs/libEGL.so.1.0.0 | grep -c "EGL_EXT_platform_wayland" || true
aarch64-linux-gnu-strip --strip-unneeded egl/.libs/libEGL.so.1.0.0 2>/dev/null || true
cd /root
rm -rf hybnw; mkdir hybnw
cp -L /root/ub-sf2/hybris/egl/.libs/libEGL.so.1.0.0 hybnw/
cd hybnw
echo -n "PACK-MESA="
strings -a libEGL.so.1.0.0 | grep -c "EGL_MESA_platform_surfaceless" || true
echo -n "PACK-WL="
strings -a libEGL.so.1.0.0 | grep -c "EGL_EXT_platform_wayland" || true
ln -sf libEGL.so.1.0.0 libEGL.so.1
ln -sf libEGL.so.1.0.0 libEGL.so
tar czf /root/hybnw.tar.gz .
ls -la /root/hybnw.tar.gz
md5sum libEGL.so.1.0.0

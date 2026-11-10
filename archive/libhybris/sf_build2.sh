#!/bin/bash
set -e
cd /root/ub-sf/hybris
for d in common platforms/common egl/platforms/common egl/platforms/null egl/platforms/fbdev egl glesv2; do
  log="/tmp/sfb_$(echo "$d" | tr '/' '_').log"
  if make -C "$d" -j4 >"$log" 2>&1; then
    echo "OK $d"
  else
    echo "FAIL $d"; tail -8 "$log"
  fi
done
echo -n "STRINGS="
strings egl/.libs/libEGL.so.1.0.0 | grep -c "MESA_platform_surfaceless" || true
aarch64-linux-gnu-strip --strip-unneeded egl/.libs/libEGL.so.1.0.0 2>/dev/null || true
cd /root
rm -rf hybsf; mkdir hybsf
cp -L /root/ub-sf/hybris/egl/.libs/libEGL.so.1.0.0 hybsf/
cd hybsf
echo -n "PACK-STRINGS="
strings -a libEGL.so.1.0.0 | grep -c "MESA_platform_surfaceless" || true
ln -sf libEGL.so.1.0.0 libEGL.so.1
ln -sf libEGL.so.1.0.0 libEGL.so
tar czf /root/hybsf.tar.gz .
ls -la /root/hybsf.tar.gz
md5sum libEGL.so.1.0.0

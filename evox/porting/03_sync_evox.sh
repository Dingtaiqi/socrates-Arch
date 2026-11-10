#!/usr/bin/env bash
# ============================================================
# 03: 同步 EvoX (Android 17 / 12.x, branch cnb) 源码 + socrates 设备栈
# 依赖: 已跑 01_env.sh + 02_pick_mirror.sh
# ============================================================
set -e
cd /build/evox
export PATH="$HOME/bin:$PATH"

echo "== repo init (EvoX cnb) =="
if [ ! -d .repo ]; then
  repo init -u https://github.com/Evolution-X/manifest -b cnb --git-lfs --no-clone-bundle
fi

echo "== local_manifest: socrates 设备栈 =="
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/socrates.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="LineageOS/android_device_xiaomi_socrates"               path="device/xiaomi/socrates"            revision="lineage-24.0" />
  <project name="LineageOS/android_device_xiaomi_sm8550-common"          path="device/xiaomi/sm8550-common"       revision="lineage-24.0" />
  <project name="LineageOS/android_kernel_xiaomi_sm8550"                 path="kernel/xiaomi/sm8550"              revision="lineage-24.0" />
  <project name="LineageOS/android_kernel_xiaomi_sm8550-devicetrees"     path="kernel/xiaomi/sm8550-devicetrees"  revision="lineage-24.0" />
  <project name="LineageOS/android_kernel_xiaomi_sm8550-modules"         path="kernel/xiaomi/sm8550-modules"      revision="lineage-24.0" />
  <project name="LineageOS/android_hardware_xiaomi"                      path="hardware/xiaomi"                   revision="lineage-24.0" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_socrates"          path="vendor/xiaomi/socrates"            revision="lineage-24.0" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_sm8550-common"     path="vendor/xiaomi/sm8550-common"       revision="lineage-24.0" />
</manifest>
XML
echo "local_manifest written"

echo "== 分支可用性检查 =="
for r in \
  LineageOS/android_device_xiaomi_socrates \
  LineageOS/android_device_xiaomi_sm8550-common \
  LineageOS/android_kernel_xiaomi_sm8550 \
  LineageOS/android_kernel_xiaomi_sm8550-devicetrees \
  LineageOS/android_kernel_xiaomi_sm8550-modules \
  LineageOS/android_hardware_xiaomi \
  TheMuppets/proprietary_vendor_xiaomi_socrates \
  TheMuppets/proprietary_vendor_xiaomi_sm8550-common ; do
  echo -n "$r: "
  git ls-remote --heads "https://github.com/$r" 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^lineage-24' | tr '\n' ' ' ; echo
done

echo "== repo sync（缺失仓库容错）=="
set +e
for i in 1 2 3; do
  echo "--- sync attempt $i ---"
  repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --optimized-fetch 2>&1 | tail -40
  if repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --optimized-fetch --local-only >/dev/null 2>&1; then
    echo "sync OK"; break
  fi
  sleep 10
done
set -e
echo "== 结果 =="
du -sh /build/evox 2>/dev/null
ls device/xiaomi 2>/dev/null || echo "device/xiaomi missing (稍后由 04 处理)"
echo "SYNC DONE"

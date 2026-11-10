#!/usr/bin/env bash
# ============================================================
# 05: 构建 EvoX for socrates
# 用法: bash 05_build.sh [userdebug|user]
# 说明: EvoX cnb (A17) 的 vendor/lineage/vars/aosp_target_release=cp2a，
#       lunch 目标形如 lineage_socrates-cp2a-userdebug（不是 lineage_socrates-userdebug）
# ============================================================
set -e
VARIANT="${1:-userdebug}"
cd /build/evox
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G >/dev/null 2>&1 || true
source build/envsetup.sh

echo "== 可用 socrates lunch 目标 =="
lunch 2>/dev/null | grep -i socrates || true

TARGET=""
for t in \
  "lineage_socrates-cp2a-${VARIANT}" \
  "lineage_socrates-${VARIANT}" \
  "socrates-${VARIANT}" ; do
  if lunch "$t" >/tmp/lunch_out 2>&1; then TARGET="$t"; break; fi
done
if [ -z "$TARGET" ]; then
  echo "!! 找不到可 lunch 的 socrates 目标，最后尝试 breakfast socrates"
  if breakfast socrates >/tmp/lunch_out 2>&1; then TARGET="(breakfast)"; fi
fi
echo "TARGET=$TARGET"

echo "== 开始构建 (m evolution -j$(nproc)) =="
mkdir -p /build/logs
LOG=/build/logs/build_$(date +%Y%m%d_%H%M%S).log
set +e
m evolution -j"$(nproc)" 2>&1 | tee "$LOG" | tail -100
RC=${PIPESTATUS[0]}
set -e
echo "build_rc=$RC log=$LOG"
echo "== 产物 =="
ls -la out/target/product/socrates/*.img out/target/product/socrates/*.zip 2>/dev/null | tail -25
echo "BUILD DONE rc=$RC"

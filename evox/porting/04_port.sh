#!/usr/bin/env bash
# ============================================================
# 04: 把 LineageOS 24 的 socrates 设备树改造成 EvoX 可用
#     （EvoX 设备树 = LineageOS 设备树 fork，主要差异：dependencies 文件名/少量配置）
# ============================================================
set -e
cd /build/evox

echo "== 1. dependencies 文件改名 =="
for d in device/xiaomi/socrates device/xiaomi/sm8550-common ; do
  [ -d "$d" ] || { echo "skip $d"; continue; }
  if [ -f "$d/lineage.dependencies" ] && [ ! -f "$d/evolution.dependencies" ]; then
    cp "$d/lineage.dependencies" "$d/evolution.dependencies"
    echo "created $d/evolution.dependencies"
  fi
done

echo "== 2. 检查 product makefile / lunch 目标 =="
cat device/xiaomi/socrates/AndroidProducts.mk
echo "---- lineage_socrates.mk head ----"
head -40 device/xiaomi/socrates/lineage_socrates.mk

echo "== 3. 检查 EvoX 构建系统支持 =="
ls build/make/target/product/*.mk >/dev/null 2>&1 && echo "build/make ok"
[ -d vendor/evolution ] && echo "vendor/evolution ok" || echo "WARN: vendor/evolution missing"
[ -d vendor/lineage ] && echo "vendor/lineage ok" || echo "INFO: vendor/lineage missing (EvoX 12 可能已移除)"
[ -d packages/apps/EvolutionSettings ] || [ -d packages/apps/Evolver ] && echo "EvoX settings app ok" || true

echo "== 4. 清理 Lineage 专属残留（保守：只打印不删除）=="
grep -rn "lineage.dependencies" device/xiaomi/socrates device/xiaomi/sm8550-common 2>/dev/null | head -5 || true
grep -rn "lineage_" device/xiaomi/socrates/*.mk device/xiaomi/sm8550-common/*.mk 2>/dev/null | head -20 || true

echo "== 5. 同步 kernel 源码存在性 =="
ls -d kernel/xiaomi/sm8550 kernel/xiaomi/sm8550-devicetrees kernel/xiaomi/sm8550-modules 2>/dev/null || echo "WARN kernel dirs missing"

echo "== 6. vendor blobs 存在性 =="
ls vendor/xiaomi/socrates 2>/dev/null | head -5
ls vendor/xiaomi/sm8550-common 2>/dev/null | head -5

echo "PORT SCRIPT DONE（下一步：bash 05_build.sh，按报错迭代）"

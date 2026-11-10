#!/usr/bin/env python3
# 把模板 patch_dsu_compat.sh 的 install_dsu_multi.sh 生成段改成 v3 顺序：
#   安装三镜像 -> 先 arm(带校验/失败手动补救) -> arm 成功后才清理 tmp -> 状态
import shutil

path = "/home/qinghuo/server_scripts/patch_dsu_compat.sh"
shutil.copy2(path, path + ".30342a6e.bak")
src = open(path).read()

OLD = '''if [ "${KEEP_IMAGES:-0}" != "1" ]; then
  for f in "$IMG_SYSTEM" "$IMG_SYSTEM_EXT" "$IMG_PRODUCT" "$IMG_SYSTEM.gz" "$IMG_SYSTEM_EXT.gz" "$IMG_PRODUCT.gz"; do
    if [ -f "$f" ]; then rm -f "$f" && echo "已清理临时镜像: $f"; fi
  done
  sync
fi

say "6. 双保险：写 one-shot arm 标志（只启动一次 DSU，失败自动回宿主）"
mkdir -p /metadata/gsi/dsu || die "无法创建 /metadata/gsi/dsu"
printf '0' > /metadata/gsi/dsu/install_status || die "写 install_status 失败"
printf '1' > /metadata/gsi/dsu/one_shot_boot || die "写 one_shot_boot 失败"
printf 'dsu' > /metadata/gsi/dsu/active || die "写 active 失败"
rm -f /metadata/gsi/dsu/booted
sync
'''

NEW = '''say "6. 先写 one-shot arm 标志（只启动一次 DSU，失败自动回宿主；失败则保留 tmp 可重试）"
mkdir -p /metadata/gsi/dsu || die "无法创建 /metadata/gsi/dsu"
arm_ok=1
printf '0' > /metadata/gsi/dsu/install_status 2>/dev/null || arm_ok=0
printf '1' > /metadata/gsi/dsu/one_shot_boot 2>/dev/null || arm_ok=0
printf 'dsu' > /metadata/gsi/dsu/active 2>/dev/null || arm_ok=0
rm -f /metadata/gsi/dsu/booted
sync
if [ "$arm_ok" != "1" ]; then
  echo "ERROR: arm 标志写入失败（镜像已安装，tmp 未清理）手动补救：" >&2
  echo "  printf 0 >/metadata/gsi/dsu/install_status; printf 1 >/metadata/gsi/dsu/one_shot_boot; printf dsu >/metadata/gsi/dsu/active; rm -f /metadata/gsi/dsu/booted; sync" >&2
  die "arm 失败：执行上面的命令后 adb reboot"
fi
echo "  arm 标志写入成功"

if [ "${KEEP_IMAGES:-0}" != "1" ]; then
  say "6b. 清理 /data/local/tmp 临时镜像（arm 成功后才清理；KEEP_IMAGES=1 可保留）"
  for f in "$IMG_SYSTEM" "$IMG_SYSTEM_EXT" "$IMG_PRODUCT" "$IMG_SYSTEM.gz" "$IMG_SYSTEM_EXT.gz" "$IMG_PRODUCT.gz"; do
    if [ -f "$f" ]; then rm -f "$f" && echo "已清理临时镜像: $f"; fi
  done
  sync
fi
'''

if OLD in src:
    src = src.replace(OLD, NEW, 1)
    open(path, "w").write(src)
    print("patched: arm-before-cleanup in template")
else:
    print("ERROR: pattern not found in template")
    raise SystemExit(1)

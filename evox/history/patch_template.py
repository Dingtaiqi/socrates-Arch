#!/usr/bin/env python3
# 修正 patch_dsu_compat.sh 中 install_dsu_multi.sh 模板：
# 1) /data 峰值动态计算（含本机镜像副本；raw→~19GiB、gz→~16.4GiB）
# 2) raw/gz 自动选择 + gz 流式安装
# 3) 安装成功后清理 /data/local/tmp 临时镜像（KEEP_IMAGES=1 保留）
# 4) 重启前对 /data/gsi/dsu/dsu/*_gsi.img 大小校验
# 5) 修正 lp_names 提示路径
import shutil
import sys

path = "/home/qinghuo/server_scripts/patch_dsu_compat.sh"
shutil.copy2(path, path + ".bak")
src = open(path).read()

R1_OLD = (
    "  NEED_KB=$(( (SIZE_SYSTEM + SIZE_SYSTEM_EXT + SIZE_PRODUCT + USERDATA_SIZE) / 1024 + 262144 ))\n"
    "  echo \"/data 可用约 $((AVAIL_KB / 1024)) MiB，预计需要 $((NEED_KB / 1024)) MiB（3 镜像 + userdata + 256MiB 余量）\"\n"
    "  [ \"$AVAIL_KB\" -lt \"$NEED_KB\" ] && die \"/data 空间不足：先 gsi_tool wipe 清旧 DSU，或清理 /data/local/tmp\""
)
R1_NEW = (
    "  LOCAL_B=0\n"
    "  for f in \"$IMG_SYSTEM\" \"$IMG_SYSTEM_EXT\" \"$IMG_PRODUCT\" \"$IMG_SYSTEM.gz\" \"$IMG_SYSTEM_EXT.gz\" \"$IMG_PRODUCT.gz\"; do\n"
    "    if [ -f \"$f\" ]; then\n"
    "      SZ=$(stat -c %s \"$f\" 2>/dev/null || echo 0)\n"
    "      case \"$SZ\" in ''|*[!0-9]*) SZ=0 ;; esac\n"
    "      LOCAL_B=$((LOCAL_B + SZ))\n"
    "    fi\n"
    "  done\n"
    "  NEED_KB=$(( (LOCAL_B + SIZE_SYSTEM + SIZE_SYSTEM_EXT + SIZE_PRODUCT + USERDATA_SIZE) / 1024 + 262144 ))\n"
    "  echo \"/data 可用约 $((AVAIL_KB / 1024)) MiB；安装峰值约 $((NEED_KB / 1024)) MiB\"\n"
    "  echo \"  峰值 = 本机镜像副本 $((LOCAL_B / 1048576)) MiB(raw+gz 都计) + DSU 副本 $(((SIZE_SYSTEM + SIZE_SYSTEM_EXT + SIZE_PRODUCT) / 1048576)) MiB + userdata $((USERDATA_SIZE / 1048576)) MiB + 256 MiB\"\n"
    "  [ \"$AVAIL_KB\" -lt \"$NEED_KB\" ] && die \"/data 空间不足（峰值 $((NEED_KB / 1024)) MiB）：可改用 gz 流式（少占 raw 空间）、逐件 push->装->rm，或先 gsi_tool wipe / 清理 /data/local/tmp\""
)

R2_OLD = (
    "check_img \"$IMG_SYSTEM\" \"$SIZE_SYSTEM\"\n"
    "check_img \"$IMG_SYSTEM_EXT\" \"$SIZE_SYSTEM_EXT\"\n"
    "check_img \"$IMG_PRODUCT\" \"$SIZE_PRODUCT\""
)
R2_NEW = (
    "check_any() { # raw 期望大小\n"
    "  if [ -f \"$1\" ]; then\n"
    "    check_img \"$1\" \"$2\"\n"
    "  elif [ -f \"$1.gz\" ] && command -v gzip >/dev/null 2>&1; then\n"
    "    echo \"  OK $1.gz（gz 流式安装）\"\n"
    "  else\n"
    "    die \"缺少镜像: $1 或 $1.gz（先 adb push 到 /data/local/tmp/）\"\n"
    "  fi\n"
    "}\n"
    "check_any \"$IMG_SYSTEM\" \"$SIZE_SYSTEM\"\n"
    "check_any \"$IMG_SYSTEM_EXT\" \"$SIZE_SYSTEM_EXT\"\n"
    "check_any \"$IMG_PRODUCT\" \"$SIZE_PRODUCT\""
)

R3_OLD = (
    "say \"3. 安装 system（含 DSU userdata 镜像，约 2~10 分钟，勿断电）\"\n"
    "cat \"$IMG_SYSTEM\" | gsi_tool install --gsi-size \"$SIZE_SYSTEM\" --userdata-size \"$USERDATA_SIZE\" --no-reboot || recover\n"
    "echo \"system 安装 OK\"\n"
    "\n"
    "say \"4. 安装 system_ext 分区\"\n"
    "cat \"$IMG_SYSTEM_EXT\" | gsi_tool install --partition-name system_ext --gsi-size \"$SIZE_SYSTEM_EXT\" --no-reboot || recover\n"
    "echo \"system_ext 安装 OK\"\n"
    "\n"
    "say \"5. 安装 product 分区\"\n"
    "cat \"$IMG_PRODUCT\" | gsi_tool install --partition-name product --gsi-size \"$SIZE_PRODUCT\" --no-reboot || recover\n"
    "echo \"product 安装 OK\""
)
R3_NEW = (
    "install_part() { # raw 期望size [额外 gsi_tool 参数...]\n"
    "  IP_RAW=$1; IP_SIZE=$2; shift 2\n"
    "  if [ -f \"$IP_RAW\" ]; then\n"
    "    cat \"$IP_RAW\" | gsi_tool install --gsi-size \"$IP_SIZE\" \"$@\" --no-reboot || recover\n"
    "  elif [ -f \"$IP_RAW.gz\" ] && command -v gzip >/dev/null 2>&1; then\n"
    "    echo \"  流式安装: $IP_RAW.gz\"\n"
    "    gzip -dc \"$IP_RAW.gz\" | gsi_tool install --gsi-size \"$IP_SIZE\" \"$@\" --no-reboot || recover\n"
    "  else\n"
    "    die \"缺少镜像: $IP_RAW 或 $IP_RAW.gz\"\n"
    "  fi\n"
    "}\n"
    "\n"
    "say \"3. 安装 system（含 DSU userdata 镜像，约 2~10 分钟，勿断电）\"\n"
    "install_part \"$IMG_SYSTEM\" \"$SIZE_SYSTEM\" --userdata-size \"$USERDATA_SIZE\"\n"
    "echo \"system 安装 OK\"\n"
    "\n"
    "say \"4. 安装 system_ext 分区\"\n"
    "install_part \"$IMG_SYSTEM_EXT\" \"$SIZE_SYSTEM_EXT\" --partition-name system_ext\n"
    "echo \"system_ext 安装 OK\"\n"
    "\n"
    "say \"5. 安装 product 分区\"\n"
    "install_part \"$IMG_PRODUCT\" \"$SIZE_PRODUCT\" --partition-name product\n"
    "echo \"product 安装 OK\"\n"
    "\n"
    "if [ \"${KEEP_IMAGES:-0}\" != \"1\" ]; then\n"
    "  for f in \"$IMG_SYSTEM\" \"$IMG_SYSTEM_EXT\" \"$IMG_PRODUCT\" \"$IMG_SYSTEM.gz\" \"$IMG_SYSTEM_EXT.gz\" \"$IMG_PRODUCT.gz\"; do\n"
    "    if [ -f \"$f\" ]; then rm -f \"$f\" && echo \"已清理临时镜像: $f\"; fi\n"
    "  done\n"
    "  sync\n"
    "fi"
)

R4_OLD = (
    "echo \"  su -c 'cat /metadata/gsi/dsu/lp_names'                # 期望含 system_ext_gsi,product_gsi\""
)
R4_NEW = (
    "echo \"  su -c 'ls -la /data/gsi/dsu/dsu/'                    # 重启前: 三张 *_gsi.img 大小核对\"\n"
    "echo \"  su -c 'cat /metadata/gsi/dsu/lp_names'                # 重启进 DSU 后: 期望含 system_ext_gsi,product_gsi\""
)

count = 0
for old, new in ((R1_OLD, R1_NEW), (R2_OLD, R2_NEW), (R3_OLD, R3_NEW), (R4_OLD, R4_NEW)):
    if old in src:
        src = src.replace(old, new, 1)
        count += 1
    else:
        print("WARN: pattern not found ->", old.splitlines()[0][:70])

open(path, "w").write(src)
print("patched patterns:", count)
print("template sha will be recomputed by caller")

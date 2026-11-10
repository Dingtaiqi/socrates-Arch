#!/usr/bin/env bash
# ============================================================
# patch_dsu_compat.sh — EvoX DSU 的 system_ext / product 适配后处理
#
# 背景（详见同目录 DSU_COMPAT_PLAN.md）：
#   DSU 只替换 /system；宿主的 /system_ext、/product 会由 first-stage 挂载覆盖。
#   本脚本给出两种把 EvoX 构建产物 system_ext.img / product.img 带进 DSU 的方案：
#
#   方案 A2（推荐，--mode native）：
#     把 system_ext.img / product.img 处理成 DSU 可安装的分区镜像
#     （sparse→raw、去 AVB footer、4MiB 对齐、sha256），生成手机端脚本
#     install_dsu_multi.sh：用 gsi_tool install --partition-name system_ext/product
#     装进同一个 DSU slot。宿主 first-stage 的 TransformFstabForDsu() 会自动把
#     /system_ext、/product 的挂载来源改到 DSU 镜像 —— 不需要改 init.rc。
#
#   方案 A（后备，--mode bind）：
#     把两个分区的内容复制进 DSU 镜像的 /system_ext_image、/product_image，
#     并往 /system/etc/init/hw/init.rc 追加在 second-stage `on init` 执行的
#        exec - root root -- /system/bin/toybox mount -o bind /system_ext_image /system_ext
#        exec - root root -- /system/bin/toybox mount -o bind /product_image   /product
#     （exec 是 init 内建命令、同步执行；见 DSU_COMPAT_PLAN.md §7）
#
#   方案 C（保底，--mode gsi）：不做任何处理，只校验 06 产物并打印安装命令
#     （宿主 system_ext/product 生效）。
#
#   默认 --mode auto：system_ext.img 和 product.img 都存在时走 native，否则 gsi。
#
# 前置：
#   - 先跑 server_scripts/06_make_dsu.sh（生成 $DEST/evox_socrates_system.img）
#   - 方案 A（bind）额外要求：Linux、root、loop 挂载可用、ext4 工具
#     （truncate/resize2fs/e2fsck/dumpe2fs），且 DSU 镜像与两个源镜像都是 ext4。
#
# 产物（默认 /build/out）：
#   native: evox_socrates_system_ext.img / evox_socrates_product.img
#           install_dsu_multi.sh / dsu_compat.info
#   bind:   evox_socrates_system_compat.img（= 06 产物副本 + 补丁）
#           install_dsu_compat.sh（复用 phone_install_dsu.sh 模板）/ dsu_compat.info
#
# 安全红线：
#   - 不连接服务器/手机以外的任何东西；不 dd 写 userdata、不碰宿主分区/vendor_boot。
#   - bind 模式只写 $DEST 下的新文件，从 06 产物重新生成（幂等）。
#   - 手机端安装脚本只调用 gsi_tool。
#
# 用法：
#   bash patch_dsu_compat.sh [--mode auto|native|bind|gsi] [选项]
#   bash patch_dsu_compat.sh --mode bind --dry-run
#   bash patch_dsu_compat.sh --mode native --image /build/out/evox_socrates_system.img
#
# 可用环境变量：EVOX_TOP / OUT_DIR / DEST_DIR / NAME / USERDATA_SIZE / ALIGN /
#               TRIGGER / EXTRA_SPACE_MB
# ============================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# ---------------- 参数默认值 ----------------
MODE=${MODE:-auto}
TOP=${EVOX_TOP:-/build/evox}
OUT=${OUT_DIR:-$TOP/out/target/product/socrates}
DEST=${DEST_DIR:-/build/out}
NAME=${NAME:-evox_socrates_system.img}
USERDATA_SIZE=${USERDATA_SIZE:-8589934592}
ALIGN=${ALIGN:-4194304}
TRIGGER=${TRIGGER:-init}
EXTRA_SPACE_MB=${EXTRA_SPACE_MB:-auto}

IMAGE_OVERRIDE=""
SE_OVERRIDE=""
PR_OVERRIDE=""
DRY_RUN=0
FORCE=0

MARKER_BEGIN='# >>> DSU_COMPAT_BIND_BEGIN (managed by server_scripts/patch_dsu_compat.sh; do not edit) >>>'
MARKER_END='# <<< DSU_COMPAT_BIND_END <<<'

# 运行期全局状态
DSU_IMG_TYPE=""
DSU_IMG_SIZE=0
PREPARED_FS=""
INIT_RC_SHA=""

# ---------------- 日志 ----------------
log()  { printf '\n== %s ==\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[FATAL] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------- 清理 ----------------
MOUNT_DIRS=()
TMP_DIRS=()
CLEANUP_DONE=0
cleanup() {
  [ "$CLEANUP_DONE" = "1" ] && return 0
  CLEANUP_DONE=1
  local i d
  set +e
  for ((i=${#MOUNT_DIRS[@]}-1; i>=0; i--)); do
    umount "${MOUNT_DIRS[$i]}" 2>/dev/null
  done
  for d in "${TMP_DIRS[@]}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  set -e
}
trap cleanup EXIT INT TERM

# ---------------- 帮助 ----------------
usage() {
  cat <<'USAGE'
用法: bash patch_dsu_compat.sh [选项]

把 EvoX 构建产物的 system_ext/product 带进 DSU。详见 DSU_COMPAT_PLAN.md。

方案（--mode）:
  auto    默认；system_ext.img + product.img 存在 → native，否则 gsi
  native  方案 A2（推荐）：生成可安装的 extras 分区镜像 + install_dsu_multi.sh
  bind    方案 A（后备）：把内容塞进 DSU 镜像 + 注入 init.rc bind mount
  gsi     方案 C（保底）：不处理，只校验并打印用宿主 system_ext/product 的安装命令

常用选项:
  --image PATH            06 产物 DSU 镜像（默认 $DEST_DIR/evox_socrates_system.img）
  --build-out DIR         构建产物目录（默认 $EVOX_TOP/out/target/product/socrates）
  --outdir DIR            输出目录（默认 /build/out）
  --system-ext PATH       指定 system_ext.img
  --product PATH          指定 product.img
  --userdata-size BYTES   DSU userdata 大小（默认 8589934592 = 8GiB）
  --align BYTES           镜像对齐（默认 4194304 = 4MiB）
  --trigger init|late-init  bind 注入点的 init trigger（默认 init）
  --extra-space-mb N      bind 模式扩容预留余量 MB（默认 auto）
  --dry-run               只校验并打印计划，不写文件
  --force                 允许覆盖已存在的输出文件
  -h, --help              显示本帮助

环境变量: EVOX_TOP OUT_DIR DEST_DIR NAME USERDATA_SIZE ALIGN TRIGGER EXTRA_SPACE_MB

示例:
  bash server_scripts/06_make_dsu.sh
  bash server_scripts/patch_dsu_compat.sh --mode native
  bash server_scripts/patch_dsu_compat.sh --mode bind --dry-run
  bash server_scripts/patch_dsu_compat.sh --mode bind
USAGE
}

# ---------------- 参数解析 ----------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)            [ "$#" -ge 2 ] || die "--mode 需要参数"; MODE=$2; shift 2 ;;
    --mode=*)          MODE=${1#*=}; shift ;;
    --image)           [ "$#" -ge 2 ] || die "--image 需要参数"; IMAGE_OVERRIDE=$2; shift 2 ;;
    --image=*)         IMAGE_OVERRIDE=${1#*=}; shift ;;
    --build-out)       [ "$#" -ge 2 ] || die "--build-out 需要参数"; OUT=$2; shift 2 ;;
    --build-out=*)     OUT=${1#*=}; shift ;;
    --outdir)          [ "$#" -ge 2 ] || die "--outdir 需要参数"; DEST=$2; shift 2 ;;
    --outdir=*)        DEST=${1#*=}; shift ;;
    --system-ext)      [ "$#" -ge 2 ] || die "--system-ext 需要参数"; SE_OVERRIDE=$2; shift 2 ;;
    --system-ext=*)    SE_OVERRIDE=${1#*=}; shift ;;
    --product)         [ "$#" -ge 2 ] || die "--product 需要参数"; PR_OVERRIDE=$2; shift 2 ;;
    --product=*)       PR_OVERRIDE=${1#*=}; shift ;;
    --userdata-size)   [ "$#" -ge 2 ] || die "--userdata-size 需要参数"; USERDATA_SIZE=$2; shift 2 ;;
    --align)           [ "$#" -ge 2 ] || die "--align 需要参数"; ALIGN=$2; shift 2 ;;
    --trigger)         [ "$#" -ge 2 ] || die "--trigger 需要参数"; TRIGGER=$2; shift 2 ;;
    --extra-space-mb)  [ "$#" -ge 2 ] || die "--extra-space-mb 需要参数"; EXTRA_SPACE_MB=$2; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --force)           FORCE=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) die "未知参数: $1（用 --help 查看用法）" ;;
  esac
done

case "$MODE" in auto|native|bind|gsi) ;; *) die "--mode 只能是 auto|native|bind|gsi（当前: $MODE）" ;; esac
case "$TRIGGER" in init|late-init) ;; *) die "--trigger 只能是 init|late-init（当前: $TRIGGER）" ;; esac

case "$USERDATA_SIZE" in ''|*[!0-9]*) die "USERDATA_SIZE 必须是纯数字字节数: $USERDATA_SIZE" ;; esac
case "$ALIGN" in ''|*[!0-9]*) die "ALIGN 必须是纯数字字节数: $ALIGN" ;; esac
if [ "$EXTRA_SPACE_MB" != "auto" ]; then
  case "$EXTRA_SPACE_MB" in ''|*[!0-9]*) die "--extra-space-mb 必须是数字或 auto: $EXTRA_SPACE_MB" ;; esac
fi

# ---------------- 路径 ----------------
DSU_IMG=${IMAGE_OVERRIDE:-$DEST/$NAME}
[ -n "${IMAGE_OVERRIDE:-}" ] || true
SE_IMG=${SE_OVERRIDE:-$OUT/system_ext.img}
PR_IMG=${PR_OVERRIDE:-$OUT/product.img}
STEM=${NAME%.img}
# 分区名前缀：evox_socrates_system.img -> evox_socrates（避免 evox_socrates_system_system_ext.img 这种双 system）
PFX=$STEM
case "$STEM" in
  *_system) PFX=${STEM%_system} ;;
esac

# ---------------- 通用工具函数 ----------------
fs_type_of() { # 输出 ext4/erofs/sparse/unknown
  local f=$1 m first
  first=$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \r\n' || true)
  if [ "$first" = "3dff26ed" ]; then echo sparse; return; fi
  m=$(od -An -tx1 -j1080 -N2 "$f" 2>/dev/null | tr -d ' \r\n' || true)
  if [ "$m" = "53ef" ]; then echo ext4; return; fi
  m=$(od -An -tx1 -j1024 -N4 "$f" 2>/dev/null | tr -d ' \r\n' || true)
  if [ "$m" = "e2e1f5e0" ]; then echo erofs; return; fi
  echo unknown
}

size_of() { stat -c%s "$1"; }

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

find_host_tool() { # $1 = 工具名；输出路径或空
  local n=$1 p
  for p in "$TOP/out/host/linux-x86/bin/$n" "$TOP/host/linux-x86/bin/$n"; do
    [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  have "$n" && { command -v "$n"; return 0; }
  return 0
}

SIMG2IMG=""
AVBTOOL=""
resolve_tools() {
  SIMG2IMG=$(find_host_tool simg2img)
  local p
  for p in "$TOP/out/host/linux-x86/bin/avbtool" "$TOP/build/make/tools/avbtool" \
           "$TOP/external/avb/avbtool.py"; do
    [ -f "$p" ] && { AVBTOOL=$p; break; }
  done
  [ -z "$AVBTOOL" ] && AVBTOOL=$(find_host_tool avbtool)
  [ -z "$SIMG2IMG" ] || [ -x "$SIMG2IMG" ] || die "simg2img 不可执行: $SIMG2IMG"
}

avb_run() {
  [ -n "$AVBTOOL" ] || die "镜像带 AVB footer，但找不到 avbtool（out/host 或 PATH）"
  if [ -x "$AVBTOOL" ]; then "$AVBTOOL" "$@"; else python3 "$AVBTOOL" "$@"; fi
}

strip_footer_if_any() { # $1 = raw 镜像
  local f=$1
  if tail -c 64 "$f" 2>/dev/null | grep -aq 'AVBf'; then
    log "去除 AVB footer: $f"
    avb_run erase_footer --image "$f" >/dev/null
  fi
}

align_up_file() { # $1 = 文件；对齐到 ALIGN
  local f=$1 sz new
  sz=$(size_of "$f")
  new=$(( (sz + ALIGN - 1) / ALIGN * ALIGN ))
  if [ "$new" -ne "$sz" ]; then
    log "尾部补零对齐: $sz -> $new 字节 ($f)"
    truncate -s "$new" "$f"
  fi
}

# 清理辅助：从挂载列表移除指定目录（其余保持顺序）
remove_mount_dir() {
  local target=$1 out=() d
  for d in "${MOUNT_DIRS[@]+"${MOUNT_DIRS[@]}"}"; do
    [ -n "$d" ] && [ "$d" != "$target" ] && out+=("$d")
  done
  MOUNT_DIRS=("${out[@]+"${out[@]}"}")
}

# 把一个构建产物处理成 raw + 去 footer + 4MiB 对齐的 DSU 可安装镜像
# 结果写到 $2，成功后设置全局 PREPARED_FS
prepare_partition_image() { # $1=src $2=dst
  local src=$1 dst=$2 t
  [ -f "$src" ] || die "找不到输入镜像: $src"
  mkdir -p "$(dirname -- "$dst")"
  # 输出路径由本脚本确定性生成，重复运行直接重建（幂等）；--force 保留给兼容
  rm -f "$dst"
  t=$(fs_type_of "$src")
  case "$t" in
    sparse)
      [ -n "$SIMG2IMG" ] || die "$src 是 sparse 镜像，但找不到 simg2img"
      log "sparse -> raw: $src"
      "$SIMG2IMG" "$src" "$dst"
      ;;
    ext4|erofs)
      cp -f "$src" "$dst"
      ;;
    *)
      die "$src 不是可识别的 ext4/erofs/sparse 镜像（magic=$t）"
      ;;
  esac
  strip_footer_if_any "$dst"
  align_up_file "$dst"
  PREPARED_FS=$(fs_type_of "$dst")
  case "$PREPARED_FS" in
    ext4|erofs) ;;
    *) die "$dst 处理后不是可识别的 ext4/erofs 镜像（magic=$PREPARED_FS）" ;;
  esac
}

# 粗略检查 ext4 镜像看起来像“分区镜像”而不是 rootfs
sanity_check_partition_image() { # $1=文件 $2=fs类型 $3=分区名
  local f=$1 t=$2 part=$3 listing
  [ "$t" = "ext4" ] || return 0
  have debugfs || { info "（无 debugfs，跳过 $part 镜像结构检查）"; return 0; }
  listing=$(debugfs -R 'ls -l /' "$f" 2>/dev/null || true)
  if [ -z "$listing" ]; then
    warn "$part: debugfs 读不出根目录，跳过结构检查"
    return 0
  fi
  if printf '%s\n' "$listing" | grep -Eq 'framework|priv-app|app'; then
    info "$part: 结构检查通过（分区镜像）"
  else
    warn "$part: 根目录没有 framework/priv-app/app，可能不是 $part 分区镜像（继续，但请人工确认）"
  fi
}

df_avail_kb() { # $1=目录
  df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# ---------------- 06 / 构建产物检查 ----------------
check_06_output() {
  log "0. 检查 DSU 镜像（06 产物）"
  if [ ! -f "$DSU_IMG" ]; then
    die "找不到 DSU 镜像: $DSU_IMG
      先跑: bash server_scripts/06_make_dsu.sh
      或用 --image 指定 06 产物路径"
  fi
  local t
  t=$(fs_type_of "$DSU_IMG")
  info "DSU 镜像 : $DSU_IMG"
  info "大小     : $(size_of "$DSU_IMG") 字节 ($(( $(size_of "$DSU_IMG") / 1048576 )) MiB)"
  info "文件系统 : $t"
  if [ "$t" = "sparse" ] || [ "$t" = "unknown" ]; then
    warn "DSU 镜像不是 raw ext4/erofs（magic=$t）；请确认 06 产物已转 raw"
  fi
  DSU_IMG_TYPE=$t
  DSU_IMG_SIZE=$(size_of "$DSU_IMG")
}

# ---------------- 方案 C：gsi ----------------
run_gsi() {
  check_06_output
  log "方案 C（纯 GSI）：不处理 system_ext/product"
  if [ -f "$OUT/system_ext.img" ] || [ -f "$OUT/product.img" ]; then
    info "检测到构建产物 system_ext.img/product.img，但它们不会被带进 DSU（宿主分区生效）"
    info "如需 EvoX 的 system_ext/product：--mode native（推荐）或 --mode bind"
  fi
  log "手机端用法（06 已生成 install_dsu.sh；手机端操作见 DSU_PHONE_GUIDE.md）"
  cat <<EOF
  adb push $DSU_IMG /data/local/tmp/
  adb push $DSU_IMG.sha256 /data/local/tmp/
  adb push $DEST/install_dsu.sh /data/local/tmp/
  adb shell
  su
  sh /data/local/tmp/install_dsu.sh /data/local/tmp/$(basename -- "$DSU_IMG")
EOF
  log "验证：启动后 /metadata/gsi/dsu/lp_names 只有 system/userdata，且 /system_ext 是宿主内容"
  log "DONE（gsi）"
}

# ---------------- 手机端脚本：方案 A2 多分区安装 ----------------
gen_multi_install_script() { # $1=system $2=se $3=pr $4=s1 $5=s2 $6=s3
  local sys=$1 se=$2 pr=$3 s1=$4 s2=$5 s3=$6 gen=$DEST/install_dsu_multi.sh
  log "生成手机端多分区安装脚本: $gen"
  cat > "$gen" <<'PHONE'
#!/system/bin/sh
# ============================================================
# install_dsu_multi.sh — 由 server_scripts/patch_dsu_compat.sh 生成
#
# 在【宿主系统 HyperOS】的 root shell 里运行（不能在 DSU 内/recovery 里）：
#   adb push <system.img> <system_ext.img> <product.img> install_dsu_multi.sh /data/local/tmp/
#   adb shell
#   su
#   sh /data/local/tmp/install_dsu_multi.sh
#
# 流程: 校验 -> gsi_tool wipe -> 装 system（含 userdata 镜像）
#       -> 装 system_ext（--partition-name）-> 装 product（--partition-name）
#       -> 幂等写 one-shot arm 标志 -> 打印状态
#
# 原理: 宿主 first-stage 会把同一个 DSU slot 里所有 <partition>_gsi 镜像 map 出来，
#       并用 TransformFstabForDsu() 把 /system_ext、/product 的挂载来源改成 DSU 镜像。
#
# 红线: 只调用 gsi_tool；绝不 dd 写 userdata / 不使用 dm 映射脚本。
# ============================================================
set -u

IMG_SYSTEM="@IMG_SYSTEM@"
IMG_SYSTEM_EXT="@IMG_SYSTEM_EXT@"
IMG_PRODUCT="@IMG_PRODUCT@"
SIZE_SYSTEM="@SIZE_SYSTEM@"
SIZE_SYSTEM_EXT="@SIZE_SYSTEM_EXT@"
SIZE_PRODUCT="@SIZE_PRODUCT@"
USERDATA_SIZE="@USERDATA_SIZE@"

say() { echo "== $* =="; }
die() { echo "ERROR: $*" >&2; exit 1; }
recover() {
  echo "!! 安装中途失败，尝试 gsi_tool disable 防止意外启动 DSU ..." >&2
  gsi_tool disable >/dev/null 2>&1 || true
  sync
  echo "已禁用 DSU（下次启动回宿主）。修复原因后重跑本脚本（建议先 gsi_tool wipe）。" >&2
  exit 1
}

say "0. 环境检查"
[ "$(id -u)" = "0" ] || die "需要 root：先 adb shell，再 su"
command -v gsi_tool >/dev/null 2>&1 || die "找不到 gsi_tool（应在宿主 /system/bin/gsi_tool）"
if [ "$(getprop ro.gsid.image_running 2>/dev/null)" = "1" ]; then
  die "当前正在 DSU 里运行；请先重启回 HyperOS 再安装"
fi

check_img() { # 路径 期望大小
  [ -f "$1" ] || die "镜像不存在: $1（先 adb push 到 /data/local/tmp/）"
  IMG_N=$(stat -c %s "$1" 2>/dev/null) || die "无法读取文件大小: $1"
  [ "$IMG_N" = "$2" ] || die "大小不一致: $1 文件 $IMG_N != 预期 $2（adb push 不完整？）"
  echo "  OK $1 ($((IMG_N / 1048576)) MiB)"
}
echo "system     = $IMG_SYSTEM"
echo "system_ext = $IMG_SYSTEM_EXT"
echo "product    = $IMG_PRODUCT"
check_any() { # raw 期望大小
  if [ -f "$1" ]; then
    check_img "$1" "$2"
  elif [ -f "$1.gz" ] && command -v gzip >/dev/null 2>&1; then
    echo "  OK $1.gz（gz 流式安装）"
  else
    die "缺少镜像: $1 或 $1.gz（先 adb push 到 /data/local/tmp/）"
  fi
}
check_any "$IMG_SYSTEM" "$SIZE_SYSTEM"
check_any "$IMG_SYSTEM_EXT" "$SIZE_SYSTEM_EXT"
check_any "$IMG_PRODUCT" "$SIZE_PRODUCT"

case "$USERDATA_SIZE" in ''|*[!0-9]*) die "USERDATA_SIZE 非法: $USERDATA_SIZE" ;; esac

say "1. /data 剩余空间"
DF_LINE=$(df -k /data 2>/dev/null | tail -n 1)
set -- $DF_LINE
AVAIL_KB=""
[ "$#" -ge 4 ] && AVAIL_KB=$4
case "$AVAIL_KB" in ''|*[!0-9]*) AVAIL_KB="" ;; esac
if [ -n "$AVAIL_KB" ]; then
  LOCAL_B=0
  for f in "$IMG_SYSTEM" "$IMG_SYSTEM_EXT" "$IMG_PRODUCT" "$IMG_SYSTEM.gz" "$IMG_SYSTEM_EXT.gz" "$IMG_PRODUCT.gz"; do
    if [ -f "$f" ]; then
      SZ=$(stat -c %s "$f" 2>/dev/null || echo 0)
      case "$SZ" in ''|*[!0-9]*) SZ=0 ;; esac
      LOCAL_B=$((LOCAL_B + SZ))
    fi
  done
  NEED_KB=$(( (LOCAL_B + SIZE_SYSTEM + SIZE_SYSTEM_EXT + SIZE_PRODUCT + USERDATA_SIZE) / 1024 + 262144 ))
  echo "/data 可用约 $((AVAIL_KB / 1024)) MiB；安装峰值约 $((NEED_KB / 1024)) MiB"
  echo "  峰值 = 本机镜像副本 $((LOCAL_B / 1048576)) MiB(raw+gz 都计) + DSU 副本 $(((SIZE_SYSTEM + SIZE_SYSTEM_EXT + SIZE_PRODUCT) / 1048576)) MiB + userdata $((USERDATA_SIZE / 1048576)) MiB + 256 MiB"
  [ "$AVAIL_KB" -lt "$NEED_KB" ] && die "/data 空间不足（峰值 $((NEED_KB / 1024)) MiB）：可改用 gz 流式（少占 raw 空间）、逐件 push->装->rm，或先 gsi_tool wipe / 清理 /data/local/tmp"
else
  echo "WARN: 无法解析 df 输出，跳过空间检查"
fi

say "2. 清理旧 DSU"
STATUS=$(gsi_tool status 2>&1) || echo "WARN: gsi_tool status 返回非 0"
echo "$STATUS"
case "$STATUS" in
  *running*) die "gsi_tool 显示 running：当前在 DSU 内运行，先重启回 HyperOS" ;;
  *installed*) gsi_tool wipe || die "gsi_tool wipe 失败"; sync; sleep 1 ;;
  *) echo "没有旧安装，跳过 wipe" ;;
esac

install_part() { # raw 期望size [额外 gsi_tool 参数...]
  IP_RAW=$1; IP_SIZE=$2; shift 2
  if [ -f "$IP_RAW" ]; then
    cat "$IP_RAW" | gsi_tool install --gsi-size "$IP_SIZE" "$@" --no-reboot || recover
  elif [ -f "$IP_RAW.gz" ] && command -v gzip >/dev/null 2>&1; then
    echo "  流式安装: $IP_RAW.gz"
    gzip -dc "$IP_RAW.gz" | gsi_tool install --gsi-size "$IP_SIZE" "$@" --no-reboot || recover
  else
    die "缺少镜像: $IP_RAW 或 $IP_RAW.gz"
  fi
}

say "3. 安装 system（含 DSU userdata 镜像，约 2~10 分钟，勿断电）"
install_part "$IMG_SYSTEM" "$SIZE_SYSTEM" --userdata-size "$USERDATA_SIZE"
echo "system 安装 OK"

say "4. 安装 system_ext 分区"
install_part "$IMG_SYSTEM_EXT" "$SIZE_SYSTEM_EXT" --partition-name system_ext
echo "system_ext 安装 OK"

say "5. 安装 product 分区"
install_part "$IMG_PRODUCT" "$SIZE_PRODUCT" --partition-name product
echo "product 安装 OK"

say "6. 先写 one-shot arm 标志（只启动一次 DSU，失败自动回宿主；失败则保留 tmp 可重试）"
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

say "7. 状态"
gsi_tool status 2>&1 || true
for f in install_status one_shot_boot active booted; do
  v=$(cat "/metadata/gsi/dsu/$f" 2>/dev/null)
  [ -z "$v" ] && echo "$f = (不存在)" || echo "$f = $v"
done
echo "lp_names (安装后可能还没生成，启动时由 first-stage 重写):"
cat /metadata/gsi/dsu/lp_names 2>/dev/null || echo "  (不存在/为空)"

echo
echo "ARMED（one-shot）。现在: adb reboot"
echo "首次启动 3~10 分钟（首次 dexopt），不要强断电。"
echo "启动后验证:"
echo "  su -c 'ls -la /data/gsi/dsu/dsu/'                    # 重启前: 三张 *_gsi.img 大小核对"
echo "  su -c 'cat /metadata/gsi/dsu/lp_names'                # 重启进 DSU 后: 期望含 system_ext_gsi,product_gsi"
echo "  su -c '[ ! -e /system_ext/etc/init/init.miui.cust.rc ] && echo EVOX_SYSTEMEXT_OK'"
echo "  su -c '[ ! -e /product/pangu ] && echo EVOX_PRODUCT_OK'"
echo "切回宿主: DSU 内直接重启；彻底删除: gsi_tool disable && gsi_tool wipe"
PHONE
  chmod +x "$gen"
  # 一次性替换占位符（用 python3 防止路径/大小里的特殊字符影响 sed）
  if have python3; then
    python3 - "$gen" "$sys" "$se" "$pr" "$s1" "$s2" "$s3" "$USERDATA_SIZE" <<'PY'
import sys
path, sysimg, se, pr, s1, s2, s3, ud = sys.argv[1:9]
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()
for k, v in (('@IMG_SYSTEM@', sysimg), ('@IMG_SYSTEM_EXT@', se), ('@IMG_PRODUCT@', pr),
             ('@SIZE_SYSTEM@', s1), ('@SIZE_SYSTEM_EXT@', s2), ('@SIZE_PRODUCT@', s3),
             ('@USERDATA_SIZE@', ud)):
    text = text.replace(k, v)
with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
PY
  else
    sed -i \
      -e "s|@IMG_SYSTEM@|$sys|g" \
      -e "s|@IMG_SYSTEM_EXT@|$se|g" \
      -e "s|@IMG_PRODUCT@|$pr|g" \
      -e "s|@SIZE_SYSTEM@|$s1|g" \
      -e "s|@SIZE_SYSTEM_EXT@|$s2|g" \
      -e "s|@SIZE_PRODUCT@|$s3|g" \
      -e "s|@USERDATA_SIZE@|$USERDATA_SIZE|g" "$gen"
  fi
  grep -q '@SIZE_SYSTEM@' "$gen" && die "手机端脚本占位符替换失败: $gen"
  info "已生成: $gen"
}

# ---------------- 方案 A2：native ----------------
run_native() {
  log "方案 A2（原生多分区 DSU）"
  check_06_output
  [ -f "$SE_IMG" ] || die "找不到 system_ext 镜像: $SE_IMG（先完成构建，或用 --system-ext 指定）"
  [ -f "$PR_IMG" ] || die "找不到 product 镜像: $PR_IMG（先完成构建，或用 --product 指定）"
  resolve_tools

  local se_dst="$DEST/${PFX}_system_ext.img"
  local pr_dst="$DEST/${PFX}_product.img"
  # 手机端脚本里写的是设备路径（/data/local/tmp/...）
  local dev_sys="/data/local/tmp/$(basename -- "$DSU_IMG")"
  local dev_se="/data/local/tmp/$(basename -- "$se_dst")"
  local dev_pr="/data/local/tmp/$(basename -- "$pr_dst")"

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN：只会做以下处理，不写文件"
    info "输入 system_ext: $SE_IMG ($(fs_type_of "$SE_IMG"), $(size_of "$SE_IMG") 字节)"
    info "输入 product   : $PR_IMG ($(fs_type_of "$PR_IMG"), $(size_of "$PR_IMG") 字节)"
    info "输出           : $se_dst / $pr_dst / install_dsu_multi.sh / dsu_compat.info"
    info "DSU 镜像       : $DSU_IMG（不改动，作为 install_dsu_multi.sh 的 system 输入）"
    log "DRY-RUN 结束（native）"
    return 0
  fi

  # 1) system_ext
  log "1/3 处理 system_ext"
  prepare_partition_image "$SE_IMG" "$se_dst"
  sanity_check_partition_image "$se_dst" "$PREPARED_FS" system_ext
  SE_FS=$PREPARED_FS
  SE_SIZE=$(size_of "$se_dst")
  SE_SHA=$(sha256_of "$se_dst")
  info "system_ext : $se_dst ($SE_FS, $SE_SIZE 字节, sha256=$SE_SHA)"

  # 2) product
  log "2/3 处理 product"
  prepare_partition_image "$PR_IMG" "$pr_dst"
  sanity_check_partition_image "$pr_dst" "$PREPARED_FS" product
  PR_FS=$PREPARED_FS
  PR_SIZE=$(size_of "$pr_dst")
  PR_SHA=$(sha256_of "$pr_dst")
  info "product    : $pr_dst ($PR_FS, $PR_SIZE 字节, sha256=$PR_SHA)"

  # 3) 手机端脚本 + 清单
  log "3/3 生成手机端安装脚本与清单"
  gen_multi_install_script "$dev_sys" "$dev_se" "$dev_pr" "$DSU_IMG_SIZE" "$SE_SIZE" "$PR_SIZE"
  ( cd "$DEST" && sha256sum "$(basename -- "$se_dst")" > "$(basename -- "$se_dst").sha256" )
  ( cd "$DEST" && sha256sum "$(basename -- "$pr_dst")" > "$(basename -- "$pr_dst").sha256" )
  cat > "$DEST/dsu_compat.info" <<EOF
mode: native
created_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)
system_image: $DSU_IMG
system_size: $DSU_IMG_SIZE
system_fs: $DSU_IMG_TYPE
system_ext: $se_dst
system_ext_size: $SE_SIZE
system_ext_fs: $SE_FS
system_ext_sha256: $SE_SHA
product: $pr_dst
product_size: $PR_SIZE
product_fs: $PR_FS
product_sha256: $PR_SHA
userdata_size: $USERDATA_SIZE
align: $ALIGN
EOF
  cat "$DEST/dsu_compat.info"

  log "完成（native）。手机端:"
  cat <<EOF
  adb push $DSU_IMG $(dirname -- "$dev_sys")/
  adb push $se_dst $(dirname -- "$dev_se")/
  adb push $pr_dst $(dirname -- "$dev_pr")/
  adb push $DEST/install_dsu_multi.sh /data/local/tmp/
  adb shell
  su
  sh /data/local/tmp/install_dsu_multi.sh
  # 看到 ARMED 后: adb reboot（首次 3~10 分钟）
EOF
}

# ---------------- 方案 A：bind ----------------
mount_ro_image() { # $1=镜像 $2=临时目录（已 create）→ 挂载到目录
  local img=$1 mnt=$2 t
  t=$(fs_type_of "$img")
  case "$t" in
    ext4)
      mount -t ext4 -o loop,ro "$img" "$mnt" 2>/dev/null && return 0
      mount -o loop,ro "$img" "$mnt" 2>/dev/null && return 0
      die "挂载 ext4 镜像失败: $img（需要 root + loop 设备；容器内可能不可用）"
      ;;
    erofs)
      mount -t erofs -o loop,ro "$img" "$mnt" 2>/dev/null && return 0
      die "挂载 erofs 镜像失败: $img（服务器内核可能不支持 erofs；请改用 --mode native）"
      ;;
    *)
      die "不支持的文件系统 ($t): $img"
      ;;
  esac
}

fsck_ext4() { # 只接受 0/1
  local f=$1 rc
  set +e
  e2fsck -f -y "$f" >/dev/null 2>&1
  rc=$?
  set -e
  case "$rc" in
    0|1) return 0 ;;
    *) die "e2fsck 失败（rc=$rc）: $f" ;;
  esac
}

ext4_free_bytes() { # $1=镜像 → 输出空闲字节数
  local f=$1 bs bc bf
  bs=$(dumpe2fs -h "$f" 2>/dev/null | awk -F: '/^Block size:/{gsub(/ /,"",$2);print $2}')
  bc=$(dumpe2fs -h "$f" 2>/dev/null | awk -F: '/^Block count:/{gsub(/ /,"",$2);print $2}')
  bf=$(dumpe2fs -h "$f" 2>/dev/null | awk -F: '/^Free blocks:/{gsub(/ /,"",$2);print $2}')
  [ -n "$bs" ] && [ -n "$bc" ] && [ -n "$bf" ] || die "无法解析 dumpe2fs 输出: $f"
  echo $(( bs * bf ))
}

grow_ext4_image() { # $1=镜像 $2=需要增加的字节数
  local f=$1 add=$2 cur new
  cur=$(size_of "$f")
  new=$(( cur + add ))
  # 先按 1GiB 粒度向上取整，再对齐 ALIGN
  new=$(( (new + 1073741824 - 1) / 1073741824 * 1073741824 ))
  new=$(( (new + ALIGN - 1) / ALIGN * ALIGN ))
  log "扩容 ext4 镜像: $cur -> $new 字节 (+$((new - cur)))"
  fsck_ext4 "$f"          # resize2fs 前必须 fsck 且未挂载
  truncate -s "$new" "$f"
  resize2fs "$f" >/dev/null 2>&1 || die "resize2fs 失败: $f"
  fsck_ext4 "$f"
}

set_selinux_label_from() { # $1=源路径 $2=目标路径（尽力而为，失败只 warn）
  have python3 || { warn "无 python3，跳过 SELinux 标签校验/补写（rsync -X 已保留）"; return 0; }
  python3 - "$1" "$2" <<'PY' || true
import os, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    v = os.getxattr(src, 'security.selinux')
except OSError:
    sys.exit(0)
try:
    os.setxattr(dst, 'security.selinux', v)
except OSError as e:
    print(f"WARN: 无法给 {dst} 写 security.selinux（{e}）", file=sys.stderr)
PY
}

copy_tree() { # $1=源挂载目录 $2=目标目录 $3=名称
  local src=$1 dst=$2 name=$3
  rm -rf "$dst"
  mkdir -p "$dst"
  if have rsync; then
    info "rsync -aHAX --numeric-ids '$src/' -> '$dst/'"
    rsync -aHAX --numeric-ids "$src/" "$dst/" || die "rsync 复制失败: $name"
  else
    info "cp -a --preserve=all '$src/.' -> '$dst/'"
    ( cp -a --preserve=all "$src/." "$dst/" ) || die "cp 复制失败: $name"
  fi
  # 把源分区根目录的 SELinux 标签复制到目标目录本身（mounton 检查用）
  set_selinux_label_from "$src" "$dst"
  local n_src n_dst
  n_src=$(find "$src" | wc -l)
  n_dst=$(find "$dst" | wc -l)
  if [ "$n_dst" -lt "$n_src" ]; then
    die "复制校验失败: $name 源 $n_src 项, 目标 $n_dst 项"
  fi
  info "$name: 复制校验 OK（源 $n_src 项 / 目标 $n_dst 项）"
}

verify_xattrs_sample() { # $1=源 $2=目标 $3=名称
  have python3 || { warn "无 python3，跳过 xattr 抽样校验"; return 0; }
  local rc=0
  set +e
  python3 - "$1" "$2" "$3" <<'PY'
import os, sys
src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3]
checked = mismatch = 0
for root, dirs, files in os.walk(src):
    rel = os.path.relpath(root, src)
    for fn in files:
        s = os.path.join(root, fn)
        d = os.path.join(dst, fn) if rel == '.' else os.path.join(dst, rel, fn)
        try:
            v = os.getxattr(s, 'security.selinux')
        except OSError:
            continue
        checked += 1
        try:
            if os.getxattr(d, 'security.selinux') != v:
                mismatch += 1
        except OSError:
            mismatch += 1
        if checked >= 200:
            break
    if checked >= 200:
        break
print(f"{name}: xattr 抽样 {checked} 项，label 不一致 {mismatch} 项")
if checked and mismatch == checked:
    sys.exit(3)
PY
  rc=$?
  set -e
  [ "$rc" = "3" ] && die "xattr 校验：抽样文件全部丢失 SELinux label —— 复制方式不对（需要 root + xattr 支持）"
  return 0
}

write_marker() { # $1=目标目录 $2=源镜像 $3=sha $4=大小 $5=分区名
  local dir=$1 src=$2 sha=$3 sz=$4 part=$5
  cat > "$dir/.dsu_compat_marker" <<EOF
dsu_compat_marker=1
partition=$part
source_image=$(basename -- "$src")
source_sha256=$sha
source_size=$sz
patched_by=server_scripts/patch_dsu_compat.sh
created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  # 尽量让 marker 也有 SELinux 标签（与所在目录一致），否则 enforcing 下 shell cat 可能被拒
  set_selinux_label_from "$dir" "$dir/.dsu_compat_marker"
}

inject_init_rc() { # $1=DSU 镜像挂载点
  local mnt=$1 rc tmp
  rc="$mnt/system/etc/init/hw/init.rc"
  if [ -L "$rc" ]; then
    local t
    t=$(readlink -- "$rc")
    case "$t" in
      /*) rc="$mnt$t" ;;
      *)  rc="$(dirname -- "$rc")/$t" ;;
    esac
    info "init.rc 是符号链接，改写真身: $rc"
  fi
  [ -f "$rc" ] || die "找不到 init.rc: $mnt/system/etc/init/hw/init.rc（镜像布局不符？）"
  tmp=$(mktemp)
  # 先删掉旧的注入块（按标记块整段删除），保证幂等
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip != 1 { print }
  ' "$rc" > "$tmp"
  {
    printf '\n'
    printf '%s\n' "$MARKER_BEGIN"
    printf '# 方案 A：用 DSU 镜像里的 system_ext/product 副本覆盖宿主分区（second-stage, zygote 之前）\n'
    printf '# exec 是 init 内建命令（同步执行）；toybox mount 用保守的 -o bind 写法\n'
    printf 'on %s\n' "$TRIGGER"
    printf '    exec - root root -- /system/bin/toybox mount -o bind /system_ext_image /system_ext\n'
    printf '    exec - root root -- /system/bin/toybox mount -o bind /product_image /product\n'
    printf '%s\n' "$MARKER_END"
  } >> "$tmp"
  if ! grep -q "^on $TRIGGER$" "$tmp"; then
    rm -f "$tmp"
    die "init.rc 注入校验失败：没有找到 'on $TRIGGER'"
  fi
  # 严格校验：标记块内必须恰好包含目标 trigger 与两条 exec 行（防止 block 被吞进上一个 action）
  local block
  block=$(mktemp)
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { inside = 1 }
    inside == 1 { print }
    $0 == e { inside = 0 }
  ' "$tmp" > "$block"
  if ! grep -qx "on $TRIGGER" "$block"; then
    rm -f "$tmp" "$block"
    die "init.rc 注入校验失败：标记块内缺少 'on $TRIGGER'"
  fi
  if ! grep -qF 'exec - root root -- /system/bin/toybox mount -o bind /system_ext_image /system_ext' "$block"; then
    rm -f "$tmp" "$block"
    die "init.rc 注入校验失败：system_ext bind 行缺失"
  fi
  if ! grep -qF 'exec - root root -- /system/bin/toybox mount -o bind /product_image /product' "$block"; then
    rm -f "$tmp" "$block"
    die "init.rc 注入校验失败：product bind 行缺失"
  fi
  if [ "$(grep -cF "$MARKER_BEGIN" "$tmp")" != "1" ]; then
    rm -f "$tmp" "$block"
    die "init.rc 注入校验失败：标记块数量不为 1（旧的注入块可能未清理干净）"
  fi
  rm -f "$block"
  cat "$tmp" > "$rc"
  rm -f "$tmp"
  info "init.rc 已注入（on $TRIGGER，幂等标记块）"
  INIT_RC_SHA=$(sha256_of "$rc")
}

run_bind() {
  log "方案 A（bind mount：镜像内副本 + init.rc 注入）"
  [ "$(id -u)" = "0" ] || die "方案 A 需要 root（loop 挂载/ext4 resize）"
  for t in mount umount truncate resize2fs e2fsck dumpe2fs od sha256sum; do
    have "$t" || die "缺少工具: $t（Ubuntu: apt install e2fsprogs util-linux coreutils）"
  done
  check_06_output
  [ "$DSU_IMG_TYPE" = "ext4" ] || die "方案 A 要求 DSU 镜像是 ext4（当前: $DSU_IMG_TYPE）。
      如果 06 产物是 erofs：用 --mode native，或把镜像类型改成 ext4 后重编"
  [ -f "$SE_IMG" ] || die "找不到 system_ext 镜像: $SE_IMG（--system-ext 指定）"
  [ -f "$PR_IMG" ] || die "找不到 product 镜像: $PR_IMG（--product 指定）"
  local se_t pr_t
  se_t=$(fs_type_of "$SE_IMG")
  pr_t=$(fs_type_of "$PR_IMG")
  case "$se_t" in ext4|erofs|sparse) ;; *) die "system_ext 不是可识别的分区镜像（magic=$se_t）: $SE_IMG" ;; esac
  case "$pr_t" in ext4|erofs|sparse) ;; *) die "product 不是可识别的分区镜像（magic=$pr_t）: $PR_IMG" ;; esac
  resolve_tools

  local compat="$DEST/${STEM}_compat.img"
  local gen="$DEST/install_dsu_compat.sh"
  [ -e "$compat" ] && info "将覆盖已存在的输出: $compat（每次从 06 产物重新生成，结果确定）"

  # 计算源内容大小：挂源镜像 -> du -sb
  WORK=$(mktemp -d "$DEST/.dsu_compat_XXXXXX") || die "无法在 $DEST 下创建临时目录"
  TMP_DIRS+=("$WORK")
  local mnt_se="$WORK/mnt_system_ext" mnt_pr="$WORK/mnt_product" mnt_t="$WORK/mnt_target"
  mkdir -p "$mnt_se" "$mnt_pr" "$mnt_t"

  # 源镜像若为 sparse，先转 raw 再挂
  local se_use=$SE_IMG pr_use=$PR_IMG
  if [ "$se_t" = "sparse" ]; then
    [ -n "$SIMG2IMG" ] || die "system_ext 是 sparse 但找不到 simg2img"
    se_use="$WORK/system_ext.raw"
    "$SIMG2IMG" "$SE_IMG" "$se_use"
  fi
  if [ "$pr_t" = "sparse" ]; then
    [ -n "$SIMG2IMG" ] || die "product 是 sparse 但找不到 simg2img"
    pr_use="$WORK/product.raw"
    "$SIMG2IMG" "$PR_IMG" "$pr_use"
  fi

  log "1/6 挂载源镜像（只读）"
  mount_ro_image "$se_use" "$mnt_se"; MOUNT_DIRS+=("$mnt_se"); info "system_ext 已挂载"
  mount_ro_image "$pr_use" "$mnt_pr"; MOUNT_DIRS+=("$mnt_pr"); info "product 已挂载"
  local se_bytes pr_bytes content_bytes
  se_bytes=$(du -sb "$mnt_se" | awk '{print $1}')
  pr_bytes=$(du -sb "$mnt_pr" | awk '{print $1}')
  content_bytes=$(( se_bytes + pr_bytes ))
  info "内容大小: system_ext=$(numfmt --to=iec "$se_bytes" 2>/dev/null || echo "$se_bytes B") product=$(numfmt --to=iec "$pr_bytes" 2>/dev/null || echo "$pr_bytes B")"

  local margin
  if [ "$EXTRA_SPACE_MB" = "auto" ]; then
    margin=$(( 512 * 1024 * 1024 ))
  else
    margin=$(( EXTRA_SPACE_MB * 1024 * 1024 ))
  fi
  local required=$(( content_bytes + content_bytes / 20 + margin ))

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN：计划"
    info "复制 system_ext ($se_bytes B) -> /system_ext_image"
    info "复制 product    ($pr_bytes B) -> /product_image"
    info "DSU 镜像: $DSU_IMG（$(size_of "$DSU_IMG") B, ext4），预计复制需要 >= $required B 空闲"
    info "输出: $compat + $gen + dsu_compat.info"
    info "init.rc 注入: on $TRIGGER { toybox mount -o bind /system_ext_image /system_ext; /product_image -> /product }"
    log "DRY-RUN 结束（bind，不写文件）"
    return 0
  fi

  log "2/6 准备可写的 DSU 镜像副本"
  local work="$WORK/work.img"
  local avail_kb need_kb
  avail_kb=$(df_avail_kb "$DEST")
  need_kb=$(( (DSU_IMG_SIZE + required + 1073741824) / 1024 ))
  if [ -n "${avail_kb:-}" ] && [ "$avail_kb" -lt "$need_kb" ]; then
    die "$DEST 剩余空间不足: $((avail_kb / 1024)) MiB < 需要 $((need_kb / 1024)) MiB"
  fi
  cp -f "$DSU_IMG" "$work" || die "复制 DSU 镜像失败: $DSU_IMG -> $work"
  local wt
  wt=$(fs_type_of "$work")
  if [ "$wt" = "sparse" ]; then
    [ -n "$SIMG2IMG" ] || die "06 产物是 sparse 但找不到 simg2img"
    "$SIMG2IMG" "$work" "$WORK/work.raw"
    mv -f "$WORK/work.raw" "$work"
  fi
  strip_footer_if_any "$work"
  [ "$(fs_type_of "$work")" = "ext4" ] || die "工作镜像不是 ext4（magic=$(fs_type_of "$work")）"

  local free_bytes
  free_bytes=$(ext4_free_bytes "$work")
  info "DSU 镜像内空闲: $((free_bytes / 1048576)) MiB，需要约 $((required / 1048576)) MiB"
  if [ "$free_bytes" -lt "$required" ]; then
    log "3/6 扩容 DSU 镜像（resize2fs）"
    grow_ext4_image "$work" $(( required - free_bytes ))
    free_bytes=$(ext4_free_bytes "$work")
    [ "$free_bytes" -ge "$required" ] || die "扩容后空间仍不足: 空闲 $free_bytes < 需要 $required"
  else
    log "3/6 空间足够，跳过扩容"
  fi

  log "4/6 挂载 DSU 镜像并复制 system_ext/product 内容"
  mount -t ext4 -o loop,rw "$work" "$mnt_t" 2>/dev/null || mount -o loop,rw "$work" "$mnt_t" 2>/dev/null \
    || die "挂载 DSU 镜像失败（需要 root + loop 设备）: $work"
  MOUNT_DIRS+=("$mnt_t")

  copy_tree "$mnt_se" "$mnt_t/system_ext_image" system_ext
  copy_tree "$mnt_pr" "$mnt_t/product_image" product
  [ -d "$mnt_t/system_ext_image" ] && [ -n "$(ls -A "$mnt_t/system_ext_image" 2>/dev/null)" ] \
    || die "复制后 /system_ext_image 为空，异常退出"
  [ -d "$mnt_t/product_image" ] && [ -n "$(ls -A "$mnt_t/product_image" 2>/dev/null)" ] \
    || die "复制后 /product_image 为空，异常退出"
  verify_xattrs_sample "$mnt_se" "$mnt_t/system_ext_image" system_ext
  verify_xattrs_sample "$mnt_pr" "$mnt_t/product_image" product
  if [ ! -x "$mnt_t/system/bin/toybox" ]; then
    warn "镜像里没有 /system/bin/toybox（bind 注入执行时会失败）: $mnt_t/system/bin/toybox"
  fi
  # 源镜像已复制完，卸载
  umount "$mnt_se" 2>/dev/null || warn "卸载失败（不影响结果）: $mnt_se"
  remove_mount_dir "$mnt_se"
  umount "$mnt_pr" 2>/dev/null || warn "卸载失败（不影响结果）: $mnt_pr"
  remove_mount_dir "$mnt_pr"

  log "5/6 注入 init.rc + 写标记/清单"
  write_marker "$mnt_t/system_ext_image" "$SE_IMG" "$(sha256_of "$SE_IMG")" "$(size_of "$SE_IMG")" system_ext
  write_marker "$mnt_t/product_image" "$PR_IMG" "$(sha256_of "$PR_IMG")" "$(size_of "$PR_IMG")" product
  inject_init_rc "$mnt_t"
  cat > "$mnt_t/dsu_compat.manifest" <<EOF
mode=bind
version=1
created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
trigger=$TRIGGER
system_image=$(basename -- "$DSU_IMG")
system_ext_source=$(basename -- "$SE_IMG")
system_ext_sha256=$(sha256_of "$SE_IMG")
system_ext_size=$(size_of "$SE_IMG")
product_source=$(basename -- "$PR_IMG")
product_sha256=$(sha256_of "$PR_IMG")
product_size=$(size_of "$PR_IMG")
init_rc_sha256=$INIT_RC_SHA
EOF

  log "6/6 收尾：卸载、fsck、对齐、sha256"
  sync
  umount "$mnt_t" || die "卸载失败: $mnt_t"
  remove_mount_dir "$mnt_t"
  fsck_ext4 "$work"
  align_up_file "$work"
  mv -f "$work" "$compat"
  local final_sz final_sha
  final_sz=$(size_of "$compat")
  final_sha=$(sha256_of "$compat")
  ( cd "$DEST" && sha256sum "$(basename -- "$compat")" > "$(basename -- "$compat").sha256" )

  # 复用 phone_install_dsu.sh 模板生成手机端安装脚本
  local tpl="$SCRIPT_DIR/phone_install_dsu.sh"
  [ -f "$tpl" ] || die "找不到模板 $tpl（需要它生成手机端安装脚本）"
  sed \
    -e "s|^IMG_DEFAULT=.*|IMG_DEFAULT=\"/data/local/tmp/$(basename -- "$compat")\"|" \
    -e "s|^GSI_SIZE_DEFAULT=.*|GSI_SIZE_DEFAULT=\"$final_sz\"|" \
    -e "s|^USERDATA_SIZE_DEFAULT=.*|USERDATA_SIZE_DEFAULT=\"$USERDATA_SIZE\"|" \
    "$tpl" > "$gen"
  chmod +x "$gen"
  grep -q "^GSI_SIZE_DEFAULT=\"$final_sz\"" "$gen" || die "模板替换失败（GSI_SIZE_DEFAULT）: $gen"

  cat > "$DEST/dsu_compat.info" <<EOF
mode: bind
created_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)
compat_image: $compat
compat_size: $final_sz
compat_sha256: $final_sha
gsi_size: $final_sz
source_dsu_image: $DSU_IMG
source_dsu_size: $DSU_IMG_SIZE
system_ext_source: $SE_IMG
system_ext_source_sha256: $(sha256_of "$SE_IMG")
product_source: $PR_IMG
product_source_sha256: $(sha256_of "$PR_IMG")
init_rc_sha256: $INIT_RC_SHA
trigger: $TRIGGER
userdata_size: $USERDATA_SIZE
align: $ALIGN
EOF
  cat "$DEST/dsu_compat.info"

  log "完成（bind）。手机端:"
  cat <<EOF
  adb push $compat /data/local/tmp/
  adb push $compat.sha256 /data/local/tmp/
  adb push $gen /data/local/tmp/
  adb shell
  su
  sh /data/local/tmp/$(basename -- "$gen") /data/local/tmp/$(basename -- "$compat")
  # 看到 ARMED 后: adb reboot（首次 3~10 分钟）
  验证: su -c 'cat /system_ext_image/.dsu_compat_marker'
        su -c 'cat /proc/mounts | grep -E "system_ext|product"'
        su -c '[ ! -e /system_ext/etc/init/init.miui.cust.rc ] && echo EVOX_SYSTEMEXT_OK'
EOF
}

# ---------------- 主流程 ----------------
main() {
  log "patch_dsu_compat.sh（DSU system_ext/product 适配后处理）"
  info "mode=$MODE  dry_run=$DRY_RUN"
  info "构建产物目录: $OUT"
  info "输出目录    : $DEST"
  info "DSU 镜像    : $DSU_IMG"
  [ -d "$DEST" ] || mkdir -p "$DEST" || die "无法创建输出目录: $DEST"

  if [ "$MODE" = "auto" ]; then
    if [ -f "$SE_IMG" ] && [ -f "$PR_IMG" ]; then
      MODE=native
      log "auto -> native（推荐方案 A2：检测到 $(basename -- "$SE_IMG") / $(basename -- "$PR_IMG")）"
    else
      MODE=gsi
      log "auto -> gsi（未找到 system_ext.img/product.img，只能走方案 C；有产物时用 --mode native/bind）"
    fi
  fi

  case "$MODE" in
    native) run_native ;;
    bind)   run_bind ;;
    gsi)    run_gsi ;;
    *) die "内部错误: MODE=$MODE" ;;
  esac
}

main "$@"

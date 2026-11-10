#!/usr/bin/env bash
# ============================================================
# 07: socrates (Redmi K60 Pro / SM8550) LineageOS 24.0 设备树 → EvoX (Android 17, cnb) 适配
#
# 背景:
#   EvoX 设备树基本是 LineageOS 设备树的 fork，差别主要在:
#     1) 依赖清单文件名 lineage.dependencies → evolution.dependencies
#        （EvoX 的 vendor_evolution/build/tools/roomservice.py 只读 evolution.dependencies，
#         其默认 remote 是 evo-devices，默认分支 cnb）
#     2) product makefile 里除继承 vendor/lineage/config/common_full_phone.mk 外，
#        还要给出 EvoX 专属变量（EVO_BUILD_TYPE / TARGET_BOOT_ANIMATION_RES /
#        SURFACE_FLINGER_BOOST / soong frame rate / BUILD_FINGERPRINT /
#        PRODUCT_GMS_CLIENTID_BASE）
#     3) hardware/xiaomi 用 EvoX 自己的 fork（Evolution-X-Devices/hardware_xiaomi,
#        branch cnb-no-dolby），而不是 LineageOS/android_hardware_xiaomi
#
# 前置:
#   - 服务器源码树已 repo sync 完（先跑 03_sync_evox.sh）
#   - device/xiaomi/socrates、device/xiaomi/sm8550-common 已存在
#
# 用法:
#   bash 07_port_evox_socrates.sh
#   EVOX_TOP=/build/evox bash 07_port_evox_socrates.sh    # 覆盖源码树根目录
#
# 本脚本只写 3 类文件（全部幂等，重复执行不会重复插入/覆盖已有内容）:
#   device/xiaomi/socrates/evolution.dependencies         （不存在时从 lineage.dependencies 复制）
#   device/xiaomi/sm8550-common/evolution.dependencies    （同上）
#   device/xiaomi/socrates/lineage_socrates.mk            （缺少 EvoX 变量块时插入一次）
#
# 其余步骤（Lineage 引用扫描 / hardware/xiaomi 来源判定）全部只读，只打印警告，
# 需要人工决策的替换动作留给 Lead 执行。
# ============================================================
set -euo pipefail

TOP=${EVOX_TOP:-/build/evox}
SOC_DIR=device/xiaomi/socrates
COMMON_DIR=device/xiaomi/sm8550-common
SOC_MK=$SOC_DIR/lineage_socrates.mk

# EvoX 变量块标记（幂等判断用，勿随意改）
MARKER='# >>> EvoX port: EvoX specific configuration (added by server_scripts/07_port_evox_socrates.sh) >>>'
MARKER_END='# <<< EvoX port: end <<<'

WARN_COUNT=0
log()  { printf '\n== %s ==\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf '[WARN] %s\n' "$*"; }
die()  { printf '\n[FATAL] %s\n' "$*" >&2; exit 1; }

TMPD=$(mktemp -d 2>/dev/null || echo "/tmp/evox_port.$$")
mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

# 找一个可用的 Python（仅用于 JSON 合法性校验；repo 工具本身依赖 python3）
PYTHON=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys' >/dev/null 2>&1; then
    PYTHON=$c
    break
  fi
done

cd "$TOP" 2>/dev/null || die "找不到源码树 $TOP（先跑 03_sync_evox.sh）"

# ------------------------------------------------------------
log "STEP 0/5. 环境检查"
info "源码树: $TOP"
[ -d "$SOC_DIR" ]    || die "$TOP/$SOC_DIR 不存在：socrates 设备树未同步，先跑 03_sync_evox.sh"
[ -f "$SOC_MK" ]     || die "缺少 $SOC_MK（LineageOS socrates 设备树结构不符，请人工检查）"
if [ -d "$COMMON_DIR" ]; then
  info "sm8550-common: 存在"
else
  warn "$TOP/$COMMON_DIR 不存在（03 的 local_manifest 应同步它；本次只处理 socrates）"
fi
info "socrates 设备树版本: $(git -C "$SOC_DIR" log -1 --format='%h %cd %s' --date=short 2>/dev/null || echo 'n/a(非 git 仓库)')"
info "lineage_socrates.mk 关键定义:"
grep -nE '^PRODUCT_(NAME|DEVICE|MODEL|BRAND|MANUFACTURER)[[:space:]]*:=' "$SOC_MK" 2>/dev/null | sed 's/^/    /' || true

if [ -f vendor/lineage/config/common_full_phone.mk ]; then
  if [ -f vendor/lineage/config/version.mk ] && grep -q 'EVO_BUILD_TYPE' vendor/lineage/config/version.mk 2>/dev/null; then
    info "vendor/lineage = EvoX vendor_evolution fork（检测到 EVO_* 配置）"
  else
    warn "vendor/lineage 看起来不是 EvoX fork（缺少 EVO_* 配置）——请确认 repo init 用的是 Evolution-X/manifest cnb"
  fi
else
  warn "vendor/lineage/config/common_full_phone.mk 不存在：EvoX 源码可能不完整（vendor_evolution 未同步）"
fi

# EvoX 的 lunch 目标格式是 lineage_<device>-<aosp_target_release>-<variant>，
# <aosp_target_release> 来自 vendor/lineage/vars/aosp_target_release（cnb 当前为 cp2a）
AOSP_REL=$(sed -n 's/^aosp_target_release=//p' vendor/lineage/vars/aosp_target_release 2>/dev/null | tail -n1)
AOSP_REL=${AOSP_REL:-cp2a}
info "EvoX aosp_target_release = ${AOSP_REL}（来自 vendor/lineage/vars/aosp_target_release）"
info "建议 lunch 目标: lineage_socrates-${AOSP_REL}-userdebug   （等价于: breakfast socrates）"

# ------------------------------------------------------------
log "STEP 1/5. 生成 evolution.dependencies（从 lineage.dependencies 复制，已存在则跳过）"

# 参数: 设备树目录
gen_deps() {
  local dir=$1 src dst
  src=$dir/lineage.dependencies
  dst=$dir/evolution.dependencies

  if [ ! -d "$dir" ]; then
    warn "跳过 $dir（目录不存在）"
    return 0
  fi
  if [ ! -f "$src" ]; then
    warn "$src 不存在，无法生成 $dst（该目录可能本来就不需要依赖清单）"
    return 0
  fi
  if [ -f "$dst" ]; then
    info "已存在 $dst，跳过（幂等）"
  else
    cp -f "$src" "$dst"
    info "已生成 $dst（复制自 lineage.dependencies）"
  fi

  # JSON 合法性校验（EvoX roomservice 用 json.load 解析，格式坏会在 breakfast 时报错）
  if [ -n "$PYTHON" ]; then
    if "$PYTHON" -c 'import json,sys; json.load(open(sys.argv[1]))' "$dst" >/dev/null 2>&1; then
      info "JSON 校验通过: $dst"
    else
      warn "JSON 校验失败: $dst（roomservice 解析会报错）"
    fi
    # 打印仓库清单，方便人工核对（LineageOS 命名，和 EvoX 默认 remote 不一致）
    info "$dst 中的依赖仓库:"
    "$PYTHON" - "$dst" <<'PY' 2>/dev/null | sed 's/^/    /' || true
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    deps = json.load(f)
for dep in deps:
    print('- %s -> %s%s' % (
        dep.get('repository', '?'),
        dep.get('target_path', '?'),
        (', remote=' + dep['remote']) if dep.get('remote') else '',
    ))
PY
  else
    info "未找到可用的 python3/python，跳过 JSON 校验"
  fi
}

gen_deps "$SOC_DIR"
gen_deps "$COMMON_DIR"

cat <<'NOTE'
  [说明] evolution.dependencies 是 LineageOS 依赖清单的逐字副本，其 repository 名是
         LineageOS 命名（android_*），而 EvoX roomservice 对没有 remote 字段的条目
         默认用 remote=evo-devices（github.com/Evolution-X-Devices），只有在该
         target_path 缺失、roomservice 真正触发 repo sync 时才会拉错仓库。
         本方案所有依赖 path 已由 03_sync_evox.sh 的 local_manifest 固定，
         roomservice 会因 "已存在" 而跳过，因此本次不影响构建；
         若以后删减 local_manifest，需同步修正这些仓库名/remote（见 PORT_NOTES.md）。
NOTE

# ------------------------------------------------------------
log "STEP 2/5. 在 lineage_socrates.mk 插入 EvoX 变量块（幂等）"

# 注意: 变量块插在 "# Inherit LineageOS configurations" 之前，
# 也就是在 $(call inherit-product, vendor/lineage/config/common_full_phone.mk) 之前。
# 原因: vendor/lineage 里下面这些逻辑是在 inherit 时（include 时）立刻求值的——
#   - config/version.mk:   EVO_BUILD_TYPE ?= Unofficial + EVO_BUILD_TYPE 合法性检查
#   - config/evolution.mk: ifeq ($(SURFACE_FLINGER_BOOST),true) 加 ro.surface_flinger.uclamp.min
#   - config/common.mk:    ifeq ($(PRODUCT_GMS_CLIENTID_BASE),) 决定 ro.com.google.clientidbase
# 若照抄 marble 那样放在 inherit 之后，这三个变量在 EvoX 侧可能不生效。
cat > "$TMPD/evox_block.mk" <<'EOF'
# >>> EvoX port: EvoX specific configuration (added by server_scripts/07_port_evox_socrates.sh) >>>
# Evolution X (Android 17 / manifest branch cnb) 专属配置。
# 注意：必须位于 "inherit-product vendor/lineage/config/common_full_phone.mk" 之前，
#      因为 EvoX 的 version.mk / evolution.mk / common.mk 在 inherit 时就会读取这些变量。
EVO_BUILD_TYPE := Unofficial

# 开机动画分辨率（socrates 是 1440p 屏）
TARGET_BOOT_ANIMATION_RES := 1440

# 渲染优化 + SurfaceFlinger 高刷档位（120Hz）
SURFACE_FLINGER_BOOST := true
$(call soong_config_set,surfaceflinger,frame_rate_category_high,120)
$(call soong_config_set,surfaceflinger,frame_rate_category_min,120)

# 指纹：A16 / HyperOS OS3.0.304.0.WMKCNXM（LineageOS socrates 同款）
# 供 GMS / RCS / Play Integrity 识别；最终 ro.build.fingerprint 以构建后 getprop 为准。
BUILD_FINGERPRINT := Redmi/socrates/socrates:16/BP2A.250605.031.A3/OS3.0.304.0.WMKCNXM:user/release-keys

# GMS client id（小米）
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

# <<< EvoX port: end <<<

EOF

BLOCK_MODE=""
if grep -qF "$MARKER" "$SOC_MK"; then
  BLOCK_MODE=present
  info "已存在 EvoX 变量块（标记命中），跳过插入（幂等）"
elif grep -qE 'EVO_BUILD_TYPE[[:space:]]*:=' "$SOC_MK"; then
  BLOCK_MODE=manual
  warn "文件里已有 EVO_BUILD_TYPE 但没有本脚本标记：为避免破坏人工改动，跳过自动插入，请人工核对补齐"
else
  # 选插入锚点：优先 "# Inherit LineageOS configurations"，退化到 PRODUCT_NAME 行，再退化到文件末尾
  ANCHOR=""
  if grep -qE '^# Inherit LineageOS configurations' "$SOC_MK"; then
    ANCHOR='^# Inherit LineageOS configurations'
  elif grep -qE '^PRODUCT_NAME[[:space:]]*:=' "$SOC_MK"; then
    ANCHOR='^PRODUCT_NAME[[:space:]]*:='
    warn "lineage_socrates.mk 里没有 '# Inherit LineageOS configurations'，退化插入到 PRODUCT_NAME 之前"
  else
    warn "lineage_socrates.mk 里没有已知锚点，退化追加到文件末尾"
  fi

  # 文件若是 CRLF（正常 Linux 源码树不会），让插入块也使用 CRLF，避免混用
  if grep -q $'\r' "$SOC_MK" 2>/dev/null; then
    sed -i 's/$/\r/' "$TMPD/evox_block.mk"
    info "检测到 CRLF 换行，插入块已同步为 CRLF"
  fi

  TMPFILE="$TMPD/lineage_socrates.mk.new"
  if [ -n "$ANCHOR" ]; then
    awk -v pat="$ANCHOR" -v bf="$TMPD/evox_block.mk" '
      BEGIN {
        while ((getline ln < bf) > 0) blk = blk ln ORS
        close(bf)
        ins = 0
      }
      match($0, pat) && !ins { printf "%s", blk; ins = 1 }
      { print }
      END { if (!ins) printf "%s", blk }
    ' "$SOC_MK" > "$TMPFILE"
  else
    cp -f "$SOC_MK" "$TMPFILE"
    if [ -s "$TMPFILE" ] && [ "$(tail -c1 "$TMPFILE" | od -An -tx1 | tr -d ' \n')" != "0a" ]; then
      printf '\n' >> "$TMPFILE"
    fi
    cat "$TMPD/evox_block.mk" >> "$TMPFILE"
  fi
  mv -f "$TMPFILE" "$SOC_MK"
  BLOCK_MODE=inserted
  info "已插入 EvoX 变量块（锚点: ${ANCHOR:-文件末尾}）"
fi

# 插入结果自检
if [ "$BLOCK_MODE" = "manual" ]; then
  info "自检: 跳过（文件已有 EVO_BUILD_TYPE，本脚本未做自动修改；请人工核对是否已包含全部 EvoX 变量）"
else
  grep -qF "$MARKER" "$SOC_MK" || die "自检失败: $SOC_MK 中找不到 EvoX 变量块标记"
  info "自检: 标记存在 ✔"
  MISSING=0
  for need in 'EVO_BUILD_TYPE := Unofficial' 'TARGET_BOOT_ANIMATION_RES := 1440' \
              'SURFACE_FLINGER_BOOST := true' 'frame_rate_category_high,120' \
              'frame_rate_category_min,120' 'PRODUCT_GMS_CLIENTID_BASE := android-xiaomi'; do
    if ! grep -qF -- "$need" "$SOC_MK"; then
      if [ "$BLOCK_MODE" = "inserted" ]; then
        die "自检失败: $SOC_MK 中缺少 '$need'"
      else
        warn "自检: $SOC_MK 中缺少 '$need'"
        MISSING=1
      fi
    fi
  done
  if ! grep -qF 'BUILD_FINGERPRINT := Redmi/socrates/socrates:16/BP2A.250605.031.A3/OS3.0.304.0.WMKCNXM:user/release-keys' "$SOC_MK"; then
    if [ "$BLOCK_MODE" = "inserted" ]; then
      die "自检失败: $SOC_MK 中 BUILD_FINGERPRINT 与预期不一致"
    else
      warn "自检: $SOC_MK 中 BUILD_FINGERPRINT 与预期不一致"
      MISSING=1
    fi
  fi
  if [ "$MISSING" -eq 0 ]; then
    info "自检: 7 个 EvoX 变量全部就位 ✔"
  else
    info "自检: 变量块存在但不完整（见上面的 [WARN]），请人工补齐"
  fi
fi

info "插入位置上下文:"
grep -nE '^(EVO_BUILD_TYPE|TARGET_BOOT_ANIMATION_RES|SURFACE_FLINGER_BOOST|BUILD_FINGERPRINT|PRODUCT_GMS_CLIENTID_BASE)|^# Inherit LineageOS configurations|frame_rate_category' "$SOC_MK" \
  | tail -n 12 | sed 's/^/    /' || true

if git -C "$SOC_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  info "设备树改动摘要（git status --short）:"
  git -C "$SOC_DIR" status --short 2>/dev/null | sed 's/^/    /' || true
fi

# ------------------------------------------------------------
log "STEP 3/5. 扫描 Lineage 专属引用（只读，仅警告，不自动修改）"

# 参数: 标签、正则、目录
scan_lineage_refs() {
  local label=$1 pat=$2 dir=$3 out count
  [ -d "$dir" ] || return 0
  # 忽略纯注释行，避免命中本脚本刚插入的说明注释（真正的引用都在代码行）
  out=$(grep -rInE --include='*.mk' --include='*.bp' --include='*.rc' --include='*.prop' \
        -- "$pat" "$dir" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  if [ -n "$out" ]; then
    count=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    warn "$label: $dir 中命中 $count 处（只提示，不自动删改）:"
    printf '%s\n' "$out" | head -n 20 | sed 's/^/    /'
    if [ "$count" -gt 20 ]; then
      info "    ...（其余 $((count - 20)) 处省略）"
    fi
  fi
}

while IFS='|' read -r label pat; do
  [ -n "${label:-}" ] || continue
  scan_lineage_refs "$label" "$pat" "$SOC_DIR"
  scan_lineage_refs "$label" "$pat" "$COMMON_DIR"
done <<'PATTERNS'
lineage-sdk / Lineage SDK|lineage[-_]sdk|TARGET_DISABLE_LINEAGE_SDK
LineageParts|LineageParts
LineageSettings / LineageSettingsProvider|LineageSettings
lineage.dependencies|lineage\.dependencies
vendor/lineage 路径|vendor/lineage
org.lineageos / ro.lineage.*|org\.lineageos|ro\.lineage\.
hardware/lineage 路径|hardware/lineage
PATTERNS

cat <<'NOTE'
  [说明] EvoX cnb 的 manifest 仍提供 lineage-sdk、packages/apps/LineageParts、
         vendor/lineage（= Evolution-X/vendor_evolution，其 common.mk 会加
         LineageSettingsProvider）以及 hardware/lineage/interfaces 等，
         因此上面大部分引用可以正常解析；真正需要人工确认的是 EvoX fork 改过
         API/资源名的部分（例如 LineageParts 里被 Evolver 取代的菜单/偏好项），
         这类问题只会在编译或运行时暴露，按报错迭代即可。
NOTE

# hardware/xiaomi 引用 + dolby 引用（与 STEP 4 的硬件 HAL 换源相关）
HW_REFS=$(grep -rInE --include='*.mk' --include='*.bp' -- 'hardware/xiaomi' "$SOC_DIR" "$COMMON_DIR" 2>/dev/null || true)
if [ -n "$HW_REFS" ]; then
  info "设备树引用了 hardware/xiaomi（共 $(printf '%s\n' "$HW_REFS" | wc -l | tr -d ' ') 处），需要 EvoX fork 提供同名模块："
  printf '%s\n' "$HW_REFS" | head -n 8 | sed 's/^/    /'
fi

DOLBY_REFS=$(grep -rIni --include='*.mk' --include='*.bp' -- 'dolby' "$SOC_DIR" "$COMMON_DIR" 2>/dev/null || true)
if [ -n "$DOLBY_REFS" ]; then
  warn "设备树引用了 dolby：EvoX 的 hardware/xiaomi(cnb-no-dolby) 不含 Dolby 模块，"
  warn "      需要额外同步 Evolution-X-Devices/hardware_dolby (branch cnb) → hardware/dolby"
  printf '%s\n' "$DOLBY_REFS" | head -n 10 | sed 's/^/    /'
else
  info "设备树未引用 dolby（与 hardware_xiaomi 的 cnb-no-dolby 方案不冲突）"
fi

# ------------------------------------------------------------
log "STEP 4/5. 检查 hardware/xiaomi 来源（只读；替换动作留给 Lead）"

HW_DIR=hardware/xiaomi
if [ ! -d "$HW_DIR" ]; then
  warn "$HW_DIR 不存在（03 的 local_manifest 应同步它：LineageOS/android_hardware_xiaomi）"
else
  info "存在: $HW_DIR"
  HW_BP="$HW_DIR/Android.bp"
  if [ -f "$HW_BP" ]; then
    info "找到 $HW_BP，soong namespace 检查: $(grep -c 'soong_namespace' "$HW_BP" 2>/dev/null || echo 0) 处"
  else
    warn "$HW_BP 不存在：hardware/xiaomi 内容异常"
  fi

  # 来源判定：repo 同步的项目名记录在 .git/config 的 remote.*.projectname，
  # 手工 clone 的仓库则看 remote url；两者都抓来做文本匹配。
  HW_PROJ=$(git -C "$HW_DIR" config --get-regexp 'remote\..*\.projectname' 2>/dev/null \
            | awk 'NR==1 {print $NF}' || true)
  HW_URLS=$(git -C "$HW_DIR" remote -v 2>/dev/null || true)
  HW_CFG=$(cat "$HW_DIR/.git/config" 2>/dev/null || true)
  HW_ALL="$HW_PROJ
$HW_URLS
$HW_CFG"
  [ -n "${HW_PROJ:-}" ] && info "repo projectname: $HW_PROJ"

  if printf '%s' "$HW_ALL" | grep -qi 'Evolution-X-Devices/hardware_xiaomi'; then
    info "来源 = Evolution-X-Devices/hardware_xiaomi（EvoX fork），OK"
  elif printf '%s' "$HW_ALL" | grep -qi 'LineageOS/android_hardware_xiaomi'; then
    warn "来源 = LineageOS/android_hardware_xiaomi（LineageOS 版），不是 EvoX 期望的 fork"
    cat <<'HOWTO'
      ---- Lead 手工操作（本脚本不自动改，硬件 HAL 换源需要整体决策）----
      EvoX 参考设备树（marble）的 evolution.dependencies 约定：
        repository: Evolution-X-Devices/hardware_xiaomi
        target_path: hardware/xiaomi
        remote: github-non-los（https://github.com）
        branch: cnb-no-dolby

      A. 改 local_manifest（推荐，和 03_sync_evox.sh 保持一致）：
         在 .repo/local_manifests/socrates.xml 中把
           <project name="LineageOS/android_hardware_xiaomi" path="hardware/xiaomi" revision="lineage-24.0" />
         换成
           <project name="Evolution-X-Devices/hardware_xiaomi" path="hardware/xiaomi" revision="cnb-no-dolby" remote="github-non-los" />
         然后执行：
           rm -rf hardware/xiaomi && repo sync -c --force-sync hardware/xiaomi

      B. 只改 evolution.dependencies（roomservice 路径，需先删掉 local_manifest 里的旧条目）：
         在 device/xiaomi/socrates/evolution.dependencies 里增加
           {"repository": "Evolution-X-Devices/hardware_xiaomi", "target_path": "hardware/xiaomi", "remote": "github-non-los", "branch": "cnb-no-dolby"}
         （注意 roomservice 对同名 target_path 已存在时会跳过，所以必须先从 local_manifest 移除旧条目）

      如果之后构建报 dolby 相关缺失，再补：
        Evolution-X-Devices/hardware_dolby  branch cnb  →  hardware/dolby
HOWTO
  elif printf '%s' "$HW_ALL" | grep -qi 'hardware_xiaomi'; then
    warn "来源无法精确判定（remote 中出现 hardware_xiaomi，但不是已知 LineageOS/EvoX 命名）"
    info "当前 remote 信息:"; printf '%s\n' "$HW_URLS" | sed 's/^/    /' || true
  else
    warn "无法判定 hardware/xiaomi 来源（.git/config 缺失或不是 git 仓库）"
  fi

  # 打印 local_manifest 中的 hardware 条目，方便交叉核对
  for lm in .repo/local_manifests/*.xml; do
    [ -f "$lm" ] || continue
    if grep -q 'hardware' "$lm" 2>/dev/null; then
      info "$lm 中的 hardware 条目:"
      grep -n 'hardware' "$lm" | sed 's/^/    /'
    fi
  done
fi

# ------------------------------------------------------------
log "STEP 5/5. 摘要与下一步"

echo "  本次脚本改动:"
echo "    - device/xiaomi/socrates/evolution.dependencies       $([ -f "$SOC_DIR/evolution.dependencies" ] && echo 已就绪 || echo 未生成)"
echo "    - device/xiaomi/sm8550-common/evolution.dependencies  $([ -f "$COMMON_DIR/evolution.dependencies" ] && echo 已就绪 || echo 未生成)"
echo "    - device/xiaomi/socrates/lineage_socrates.mk          $([ -f "$SOC_MK" ] && grep -qF "$MARKER" "$SOC_MK" && echo '已含 EvoX 变量块' || echo '未含 EvoX 变量块')"
echo
echo "  lunch / 构建（05_build.sh 里硬编码的 lineage_socrates-<variant> 需要改成带 release 的形式）:"
echo "    source build/envsetup.sh"
echo "    lunch lineage_socrates-${AOSP_REL}-userdebug"
echo "    m evolution -j\$(nproc)"
echo
echo "  若 hardware/xiaomi 还没换成 EvoX fork，先按 STEP 4 的 HOWTO 处理再构建。"
echo "  回滚本脚本的改动（设备树是 git 仓库）:"
echo "    git -C device/xiaomi/socrates checkout -- lineage_socrates.mk"
echo "    rm -f device/xiaomi/socrates/evolution.dependencies device/xiaomi/sm8550-common/evolution.dependencies"
echo

if [ "$WARN_COUNT" -eq 0 ]; then
  info "共 0 条警告 ✔"
else
  info "共 $WARN_COUNT 条警告，请逐条查看上面的 [WARN]（其中 STEP 3/4 的部分需要人工决策）"
fi

echo
echo "PORT SCRIPT DONE（下一步：人工确认 STEP 4 后跑 05_build.sh，按首次报错迭代）"

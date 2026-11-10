#!/bin/bash
# ============================================================================
# srv_mkimg.sh — 通用"复制镜像 → 扩容 → loop 挂载注入 → e2fsck → sha256 → 差分"
#                流水线工具（服务器端，必须 root 运行）
#
# 用法:
#   echo '<pass>' | sudo -S -p '' bash /home/qinghuo/srv_mkimg.sh <SRC_IMG> <DST_IMG> <SPEC_DIR>
#
# SPEC_DIR 布局（全部可选，对应目录/文件不存在则跳过该步骤）:
#   add/        要注入的文件/目录树；目录层级 = 镜像内绝对路径去掉开头的 '/'
#               例: add/system/etc/init/foo.rc  ->  镜像内 /system/etc/init/foo.rc
#               目录用 mkdir（不覆盖已存在目录的属性），文件用 cp -a 写入并
#               chown 0:0。注入顺序 = inode/数据块分配顺序。
#   order.txt   可选，显式注入顺序；每行一个镜像内绝对路径（# 注释、空行忽略）。
#               不写时顺序为：浅层目录优先、同级按字典序，然后文件按字典序。
#               需要与既有镜像逐字节对齐时必须用它给出构建时的操作顺序。
#   del.txt     删除清单，每行一个镜像内绝对路径（# 开头为注释）
#               例: /system/evox_product/WebViewGoogle
#   size.txt    可选，目标字节数（单个整数，必须 4096 的倍数）；与当前大小不同则
#               增大: truncate -> e2fsck -f -y -> resize2fs
#               缩小: e2fsck -f -y -> resize2fs <blocks> -> truncate
#   rc/         要写入镜像的 rc 文本文件；rc/<镜像内路径> -> <镜像内路径>
#               例: rc/system/etc/init/zzz.rc -> /system/etc/init/zzz.rc
#               权限 644、属主 root:root、selinux xattr u:object_r:system_file:s0
#   meta.json   可选（可复现扩展）：钉住 ext4 元数据（超级块时间/挂载设备、
#               GDT flags、注入路径 inode 的 atime/ctime/mtime/crtime/generation）。
#               由 srv_cap_meta.py 从参考镜像捕获；存在则在 e2fsck 之后、sha256
#               之前做离线修补（可用 PIN_META=0 关闭）。详见 srv_pin_meta.py。
#
# 行为保证:
#   - 幂等: 每次从 SRC 重新生成 DST（先 rm -f DST），可重复运行；
#   - 失败即中止: set -euo pipefail + 关键步骤显式校验（退出码非 0 直接 exit）；
#   - 不修改 SRC；结束打印 DST 大小/sha256/差分路径；
#   - 自动生成 DST.diff（以 SRC 为锚点，gen_diff_explicit.py 显式参数版）。
#
# 环境变量（可选）:
#   MNT=/mnt/srv_mkimg   临时挂载点
#   PIN_META=0           设为 0 可强制忽略 SPEC_DIR/meta.json
# ============================================================================
set -euo pipefail

TOOL_VER="srv_mkimg.sh v1.1"
MNT=${MNT:-/mnt/srv_mkimg}
PIN_META=${PIN_META:-1}
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GEN_DIFF="$HERE/gen_diff_explicit.py"
PIN_HELPER="$HERE/srv_pin_meta.py"

log()  { printf '[srv_mkimg] %s\n' "$*"; }
die()  { printf '[srv_mkimg] ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

# ---------------- 0. 参数与环境校验 ----------------
[ "$#" -eq 3 ] || usage
SRC=$1
DST=$2
SPEC=${3%/}

[ "$(id -u)" = "0" ] || die "需要 root 运行（sudo bash $0 <SRC> <DST> <SPEC_DIR>）"
[ -f "$SRC" ] || die "SRC 镜像不存在: $SRC"
[ -s "$SRC" ] || die "SRC 镜像为空文件: $SRC"
[ -d "$SPEC" ] || die "SPEC_DIR 不存在: $SPEC"
[ "$(readlink -f "$SRC")" != "$(readlink -f "$DST" 2>/dev/null || echo "$DST")" ] || die "SRC 与 DST 不能相同: $SRC"
for c in cp truncate e2fsck resize2fs mount umount sync sha256sum stat python3; do
    have "$c" || die "缺少命令: $c"
done
[ -f "$GEN_DIFF" ] || die "缺少差分生成器: $GEN_DIFF"
[ -f "$PIN_HELPER" ] || die "缺少元数据钉扎脚本: $PIN_HELPER"

log "$TOOL_VER  $(date '+%F %T')"
log "SRC  = $SRC ($(stat -c%s "$SRC") bytes)"
log "DST  = $DST"
log "SPEC = $SPEC"

[ -d "$SPEC/add" ]      && log "add/    : $(find "$SPEC/add" -mindepth 1 | wc -l) 个条目"
[ -f "$SPEC/order.txt" ] && log "order.txt: $(grep -vcE '^\s*(#|$)' "$SPEC/order.txt" || true) 条（显式注入顺序）"
[ -f "$SPEC/del.txt" ]  && log "del.txt : $(grep -vcE '^\s*(#|$)' "$SPEC/del.txt" || true) 条"
[ -f "$SPEC/size.txt" ] && log "size.txt: $(tr -d ' \r\n' < "$SPEC/size.txt")"
[ -d "$SPEC/rc" ]       && log "rc/     : $(find "$SPEC/rc" -type f | wc -l) 个文件"
if [ -f "$SPEC/meta.json" ]; then
    log "meta.json: 存在（$([ "$PIN_META" = "0" ] && echo 'PIN_META=0，忽略' || echo '元数据钉扎模式')）"
fi

cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

# 残留挂载清理（幂等）
umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"

# ---------------- 1. 复制镜像 ----------------
log "[1/8] 复制 SRC -> DST"
rm -f "$DST"
cp -a "$SRC" "$DST"
chmod 600 "$DST"

# ---------------- 2. size.txt 扩容/缩容 ----------------
if [ -f "$SPEC/size.txt" ]; then
    TARGET=$(tr -d ' \r\n\t' < "$SPEC/size.txt")
    case "$TARGET" in ''|*[!0-9]*) die "size.txt 内容非法（需单个整数）: '$TARGET'";; esac
    [ "$TARGET" -gt 0 ] || die "size.txt 必须 > 0"
    [ $((TARGET % 4096)) -eq 0 ] || die "size.txt 必须是 4096 的整数倍: $TARGET"
    CUR=$(stat -c%s "$DST")
    if [ "$TARGET" -eq "$CUR" ]; then
        log "[2/8] size.txt 与当前大小一致（$CUR），跳过"
    elif [ "$TARGET" -gt "$CUR" ]; then
        log "[2/8] 扩容 $CUR -> $TARGET（truncate -> e2fsck -> resize2fs）"
        truncate -s "$TARGET" "$DST"
        set +e; e2fsck -f -y "$DST" >/dev/null 2>&1; FSCK_RC=$?; set -e
        [ "$FSCK_RC" -le 1 ] || die "扩容前 e2fsck 失败 rc=$FSCK_RC"
        resize2fs "$DST" 2>&1 | tail -2 | sed 's/^/[srv_mkimg]   /'
    else
        log "[2/8] 缩容 $CUR -> $TARGET（e2fsck -> resize2fs -> truncate）"
        BSIZE=$(dumpe2fs -h "$DST" 2>/dev/null | awk '/Block size/{print $3}')
        [ -n "${BSIZE:-}" ] || die "无法读取文件系统 block size"
        BLOCKS=$((TARGET / BSIZE))
        set +e; e2fsck -f -y "$DST" >/dev/null 2>&1; FSCK_RC=$?; set -e
        [ "$FSCK_RC" -le 1 ] || die "缩容前 e2fsck 失败 rc=$FSCK_RC"
        resize2fs "$DST" "$BLOCKS" 2>&1 | tail -2 | sed 's/^/[srv_mkimg]   /'
        truncate -s "$TARGET" "$DST"
    fi
else
    log "[2/8] 无 size.txt，保持原大小"
fi

# ---------------- 3. loop 挂载 ----------------
log "[3/8] loop 挂载 $DST -> $MNT"
mount -o loop,rw "$DST" "$MNT" || die "loop 挂载失败"
mountpoint -q "$MNT" || die "挂载后校验失败"

# ---------------- 4. 删除清单 ----------------
if [ -f "$SPEC/del.txt" ]; then
    log "[4/8] 删除清单"
    while IFS= read -r p || [ -n "$p" ]; do
        p=$(printf '%s' "$p" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$p" ] && continue
        case "$p" in \#*) continue;; esac
        case "$p" in /*) ;; *) die "del.txt 路径必须是镜像内绝对路径: $p";; esac
        if [ -e "$MNT$p" ] || [ -L "$MNT$p" ]; then
            rm -rf -- "$MNT$p"
            log "  DEL $p"
        else
            log "  SKIP(不存在) $p"
        fi
    done < "$SPEC/del.txt"
else
    log "[4/8] 无 del.txt，跳过"
fi

# ---------------- 5. 注入 add/ ----------------
# 注入顺序 = 内核分配 inode/数据块的顺序，直接影响镜像字节布局；需要逐字节
# 复现时用 SPEC_DIR/order.txt 显式给出顺序（与目标镜像构建时的操作顺序一致）。
inject_one() {
    local rel=$1 sp=$2 target="$MNT/$1"
    if [ -d "$sp" ]; then
        if [ -d "$target" ]; then
            log "  MERGE-DIR /$rel"
        else
            mkdir -p -- "$target"
            chown 0:0 -- "$target"
            chmod "$(stat -c%a "$sp")" -- "$target"
            log "  MKDIR /$rel mode=$(stat -c%a "$sp")"
        fi
    elif [ -f "$sp" ]; then
        mkdir -p -- "$(dirname -- "$target")"
        cp -a -- "$sp" "$target"
        chown 0:0 -- "$target"
        log "  COPY  /$rel ($(stat -c%s "$sp") bytes)"
    else
        log "  SKIP(非常规) /$rel"
    fi
}

if [ -d "$SPEC/add" ]; then
    log "[5/8] 注入 add/ 目录树（mkdir + cp -a，保留文件时间戳/权限）"
    ADD="$SPEC/add"
    declare -A DONE=()
    if [ -f "$SPEC/order.txt" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            case "$line" in \#*) continue;; esac
            case "$line" in /*) ;; *) die "order.txt 路径必须是镜像内绝对路径: $line";; esac
            rel=${line#/}
            sp="$ADD/$rel"
            [ -e "$sp" ] || die "order.txt 条目在 add/ 中不存在: $line"
            inject_one "$rel" "$sp"
            DONE["$rel"]=1
        done < "$SPEC/order.txt"
    fi
    while IFS= read -r rel; do
        [ -n "${DONE[$rel]:-}" ] && continue
        inject_one "$rel" "$ADD/$rel"
        DONE["$rel"]=1
    done < <(cd "$ADD" && find . -mindepth 1 -type d | sed 's|^\./||' \
             | awk -F/ '{print NF" "$0}' | sort -n -k1,1 -k2 | cut -d' ' -f2-)
    while IFS= read -r rel; do
        [ -n "${DONE[$rel]:-}" ] && continue
        inject_one "$rel" "$ADD/$rel"
        DONE["$rel"]=1
    done < <(cd "$ADD" && find . -mindepth 1 -type f | sed 's|^\./||' | sort)
    log "  注入条目: $(find "$ADD" -mindepth 1 | wc -l)"
else
    log "[5/8] 无 add/，跳过"
fi

# ---------------- 6. 写 rc/ ----------------
if [ -d "$SPEC/rc" ]; then
    log "[6/8] 写 rc/ 文件（644 + selinux xattr）"
    while IFS= read -r -d '' f; do
        rel=${f#"$SPEC/rc/"}
        case "$rel" in /*) die "rc/ 下路径不应以 / 开头: $rel";; esac
        tgt="$MNT/$rel"
        mkdir -p -- "$(dirname -- "$tgt")"
        cp -f -- "$f" "$tgt"
        chmod 644 -- "$tgt"
        chown 0:0 -- "$tgt"
        python3 - "$tgt" <<'PY'
import os, sys
os.setxattr(sys.argv[1], "security.selinux",
            b"u:object_r:system_file:s0\x00")
PY
        log "  RC  /$rel"
    done < <(find "$SPEC/rc" -type f -print0 | sort -z)
else
    log "[6/8] 无 rc/，跳过"
fi

# ---------------- 7. 同步/卸载/fsck ----------------
log "[7/8] sync + umount + e2fsck -f -y"
sync
umount "$MNT" || die "umount 失败"
set +e
e2fsck -f -y "$DST" > /tmp/srv_mkimg_fsck.log 2>&1
FSCK_RC=$?
set -e
tail -2 /tmp/srv_mkimg_fsck.log | sed 's/^/[srv_mkimg]   /'
[ "$FSCK_RC" -le 1 ] || die "e2fsck 失败 rc=$FSCK_RC（见 /tmp/srv_mkimg_fsck.log）"

# ---------------- 8. 可选元数据钉扎 + sha256 + 差分 ----------------
if [ -f "$SPEC/meta.json" ] && [ "$PIN_META" != "0" ]; then
    log "[8/8] 钉扎 ext4 元数据（meta.json）"
    python3 "$PIN_HELPER" "$DST" "$SPEC/meta.json" || die "元数据钉扎失败"
fi

QID=$(id -u qinghuo 2>/dev/null || echo 0)
QGID=$(id -g qinghuo 2>/dev/null || echo 0)
chown "$QID:$QGID" "$DST"
SIZE=$(stat -c%s "$DST")
SHA=$(sha256sum "$DST" | awk '{print $1}')
log "DST 大小 = $SIZE bytes"
log "DST sha256 = $SHA"

DIFF="$DST.diff"
log "生成差分 $DIFF（锚点 SRC=$SRC）"
python3 "$GEN_DIFF" "$SRC" "$DST" "$DIFF"
chown "$QID:$QGID" "$DIFF" 2>/dev/null || true
DSIZE=$(stat -c%s "$DIFF")
log "DIFF 大小 = $DSIZE bytes"
log "完成 $(date '+%F %T')"
printf 'MKTAG src=%s\ndst=%s\nsize=%s\nsha256=%s\ndiff=%s\ndiff_size=%s\n' \
    "$SRC" "$DST" "$SIZE" "$SHA" "$DIFF" "$DSIZE"
exit 0

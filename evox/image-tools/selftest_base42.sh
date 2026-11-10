#!/bin/bash
# ============================================================================
# selftest_base42.sh — srv_mkimg.sh 自检：从 base41b 逐字节重建 base42
#
#   期望 sha256 = 63a3de922bf20a8e01d5f6fed6788a79da84f13474bd9194227735b56a680a2d
#
#   产出:
#     /build/out/base42t.img        钉扎流程产物（应命中期望 sha256）
#     /build/out/base42t.img.diff   以 base41b 为锚点的 64KiB 块差分
#     /build/out/base42t_nat.img    自然流程对照（不钉扎；sha256 每次不同）
#   自检产物验证后可删（脚本末尾不删，方便复核）。
# ============================================================================
set -uo pipefail
H=/home/qinghuo
SPEC=$H/spec_base42
B=/build/evox/out/target/product/socrates
SRC=/build/out/evox_socrates_base41b.img
REF=/build/out/evox_socrates_base42.img
NAT=/build/out/base42t_nat.img
PIN=/build/out/base42t.img
EXPECT=63a3de922bf20a8e01d5f6fed6788a79da84f13474bd9194227735b56a680a2d

echo "===== 1. PREP SPEC ====="
rm -rf "$SPEC"
umask 022
mkdir -p "$SPEC/add/system/evox_product/app" "$SPEC/rc"
for d in WebViewGoogle WebViewGoogle-Stub TrichromeLibrary TrichromeLibrary-Stub; do
  mkdir -p "$SPEC/add/system/evox_product/app/$d"
done
cp -a "$B/product/app/WebViewGoogle/WebViewGoogle.apk.gz"              "$SPEC/add/system/evox_product/app/WebViewGoogle/"
cp -a "$B/product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk"      "$SPEC/add/system/evox_product/app/WebViewGoogle-Stub/"
cp -a "$B/product/app/TrichromeLibrary/TrichromeLibrary.apk.gz"        "$SPEC/add/system/evox_product/app/TrichromeLibrary/"
cp -a "$B/product/app/TrichromeLibrary-Stub/TrichromeLibrary-Stub.apk" "$SPEC/add/system/evox_product/app/TrichromeLibrary-Stub/"
find "$SPEC/add" -type d -exec chmod 755 {} +
cat > "$SPEC/del.txt" <<'EOF'
# base42: 删掉放错层级的 WebView/Trichrome（它们在 /system/evox_product 根下）
/system/evox_product/WebViewGoogle
/system/evox_product/TrichromeLibrary
EOF
cat > "$SPEC/order.txt" <<'EOF'
# base42 构建时的操作顺序（mkdir 4 个目录 → cp 4 个文件），决定 inode/数据块分配
/system/evox_product/app/WebViewGoogle
/system/evox_product/app/WebViewGoogle-Stub
/system/evox_product/app/TrichromeLibrary
/system/evox_product/app/TrichromeLibrary-Stub
/system/evox_product/app/WebViewGoogle/WebViewGoogle.apk.gz
/system/evox_product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk
/system/evox_product/app/TrichromeLibrary/TrichromeLibrary.apk.gz
/system/evox_product/app/TrichromeLibrary-Stub/TrichromeLibrary-Stub.apk
EOF
echo "spec: $(find "$SPEC/add" -type f | wc -l) files, $(du -sh "$SPEC/add" | cut -f1)"

echo "===== 2. CAPTURE META (from $REF) ====="
timeout 180 python3 "$H/srv_cap_meta.py" "$REF" "$SPEC" --sha256 || { echo CAP_FAIL; exit 1; }

echo "===== 3. CLEANUP OLD TEMP ====="
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' rm -f "$NAT" "$NAT.diff" "$PIN" "$PIN.diff"
df -h /build | tail -1

echo "===== 4. NATURAL RUN (PIN_META=0) ====="
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' env PIN_META=0 bash "$H/srv_mkimg.sh" "$SRC" "$NAT" "$SPEC" >/tmp/mk_nat.log 2>&1
echo "natural_rc=$?"; grep -E 'DST sha256|DIFF 大小|ERROR' /tmp/mk_nat.log

echo "===== 5. PINNED RUN ====="
echo 'REDACTED_BUILD_PASSWORD' | sudo -S -p '' bash "$H/srv_mkimg.sh" "$SRC" "$PIN" "$SPEC" >/tmp/mk_pin.log 2>&1
echo "pinned_rc=$?"; grep -E 'DST sha256|DST 大小|DIFF 大小|元数据钉扎|完成|ERROR' /tmp/mk_pin.log

echo "===== 6. VERIFY ====="
sha256sum "$PIN" "$NAT" "$REF"
echo "EXPECTED=$EXPECT"
if [ "$(sha256sum "$PIN" | awk '{print $1}')" = "$EXPECT" ]; then
  echo "SELFTEST_RESULT=HIT"
else
  echo "SELFTEST_RESULT=MISS"
fi
for pair in "$NAT:$REF" "$PIN:$REF"; do
  A=${pair%%:*}; BB=${pair##*:}
  echo "--- 4KiB block diff $(basename "$A") vs $(basename "$BB") ---"
  python3 - "$A" "$BB" <<'EOF'
import sys
a,b=sys.argv[1],sys.argv[2]; BS=4096
fa=open(a,'rb'); fb=open(b,'rb')
sa=fa.seek(0,2); sb=fb.seek(0,2); fa.seek(0); fb.seek(0)
diff=[]; i=0
while True:
    x=fa.read(BS); y=fb.read(BS)
    if not x and not y: break
    if x!=y: diff.append(i)
    i+=1
print("sizes", sa, sb, "total_4k_blocks", i, "diff_blocks", len(diff), "list", diff[:20])
EOF
done
echo "--- e2fsck -fn pinned ---"
e2fsck -fn "$PIN" 2>&1 | tail -2
echo "--- artifacts ---"
ls -la "$PIN" "$PIN.diff" "$NAT" "$NAT.diff" 2>/dev/null | awk '{print $5, $9}'
echo "===== SELFTEST DONE $(date +%T) ====="

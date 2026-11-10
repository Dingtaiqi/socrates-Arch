#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_diff4.py — 显式参数的块差分生成器（gen_diff3.py 的改进版，不覆盖原文件）。

用法:
    python3 gen_diff4.py <SRC_IMG> <DST_IMG> <OUT_DIFF> [BLOCK_SIZE]

格式与 gen_diff3.py 兼容:
    [4 字节小端 header 长度][JSON 头 {bs,size_src,size_dst,blocks}][变化块数据]
    blocks = 变化块索引列表（按 bs 对齐，DST 视角）

改进点:
  - 三个参数全部显式，不再用 sed 替换锚点，避免锚点替换错误；
  - 参数校验（存在/可读/非空/块大小必须是 2 的幂且 >=512）；
  - 输出 size_src/size_dst/块数/差分数据量/输出路径；
  - 支持 --quiet。
"""
import os
import json
import struct
import sys


def human(n):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0:
            return "%.2f%s" % (n, unit)
        n /= 1024.0
    return "%.2fPiB" % n


def main(argv):
    args = [a for a in argv[1:] if a != "--quiet"]
    quiet = "--quiet" in argv
    if len(args) not in (3, 4):
        sys.stderr.write(__doc__)
        return 2
    src, dst, out = args[0], args[1], args[2]
    bs = int(args[3]) if len(args) == 4 else 65536

    for tag, p in (("SRC", src), ("DST", dst)):
        if not os.path.isfile(p):
            sys.stderr.write("ERROR: %s 不存在: %s\n" % (tag, p))
            return 2
        if os.path.getsize(p) == 0:
            sys.stderr.write("ERROR: %s 为空文件: %s\n" % (tag, p))
            return 2
    if bs < 512 or (bs & (bs - 1)) != 0:
        sys.stderr.write("ERROR: BLOCK_SIZE 必须是 >=512 的 2 的幂: %r\n" % bs)
        return 2
    if os.path.abspath(src) == os.path.abspath(dst):
        sys.stderr.write("ERROR: SRC 与 DST 相同: %s\n" % src)
        return 2
    if not quiet:
        print("[gen_diff_explicit] SRC=%s (%d bytes)" % (src, os.path.getsize(src)))
        print("[gen_diff_explicit] DST=%s (%d bytes)" % (dst, os.path.getsize(dst)))
        print("[gen_diff_explicit] OUT=%s  bs=%d" % (out, bs))

    fs = os.open(src, os.O_RDONLY)
    fd = os.open(dst, os.O_RDONLY)
    try:
        size_s = os.fstat(fs).st_size
        size_d = os.fstat(fd).st_size

        def read_all(f, off, n):
            os.lseek(f, off, os.SEEK_SET)
            buf = b""
            while len(buf) < n:
                c = os.read(f, n - len(buf))
                if not c:
                    break
                buf += c
            return buf

        index = []
        data = bytearray()
        blocks = (size_d + bs - 1) // bs
        for i in range(blocks):
            off = i * bs
            db = read_all(fd, off, bs)
            sb = read_all(fs, off, bs) if off < size_s else b""
            if db != sb:
                index.append(i)
                data += db
    finally:
        os.close(fs)
        os.close(fd)

    head = json.dumps({"bs": bs, "size_src": size_s, "size_dst": size_d,
                       "blocks": index}).encode()
    tmp = out + ".tmp.%d" % os.getpid()
    with open(tmp, "wb") as f:
        f.write(struct.pack("<I", len(head)))
        f.write(head)
        f.write(data)
    os.replace(tmp, out)

    if not quiet:
        print("[gen_diff_explicit] 块大小=%d 总块数=%d 变化块=%d (%.2f%%) 差分数据=%.2f MiB"
              % (bs, blocks, len(index), 100.0 * len(index) / blocks if blocks else 0,
                 len(data) / 1048576.0))
        print("[gen_diff_explicit] 写出 %s (%d bytes = %s)" % (out, os.path.getsize(out),
                                                       human(os.path.getsize(out))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

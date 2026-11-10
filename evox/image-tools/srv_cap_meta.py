#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
srv_cap_meta.py — 从"参考镜像"捕获 meta.json（给 srv_mkimg.sh 的复现模式用）。

用法:
    python3 srv_cap_meta.py <REF_IMG> <SPEC_DIR> [--out FILE] [--sha256]

作用:
  根据 SPEC_DIR（add/、del.txt、rc/）推导出 srv_mkimg.sh 会改动到的镜像内路径
  （注入的目录/文件、被删路径的父目录、rc 写入路径，以及它们的全部祖先目录），
  再从参考镜像里捕获:
    - 超级块字段: s_mtime / s_wtime / s_lastcheck / s_last_mounted / s_kbytes_written
    - 每个 block group 的 bg_flags
    - 上述路径对应 inode 的 atime/ctime/mtime/crtime（原始 sec+extra）与 i_generation
  写入 SPEC_DIR/meta.json。之后 srv_mkimg.sh 会在 e2fsck 后用 srv_pin_meta.py
  把这些元数据钉扎回新镜像，从而使"内容相同的重建"得到逐字节相同的镜像。
"""
import json
import os
import re
import struct
import subprocess
import sys


def crc16_table():
    t = []
    for i in range(256):
        crc = i
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
        t.append(crc)
    return t


CRC16_TBL = crc16_table()


def crc16(data, crc=0xFFFF):
    for b in data:
        crc = (crc >> 8) ^ CRC16_TBL[(crc ^ b) & 0xFF]
    return crc


def read_at(f, off, n):
    f.seek(off)
    buf = b""
    while len(buf) < n:
        c = f.read(n - len(buf))
        if not c:
            break
        buf += c
    return buf


def parse_spec_paths(spec):
    """推导 SPEC 会改动到的镜像内路径集合（含祖先目录）。"""
    paths = set()

    def add_with_parents(p):
        p = "/" + p.strip("/")
        while True:
            paths.add(p)
            if p == "/":
                break
            p = os.path.dirname(p) or "/"

    add_dir = os.path.join(spec, "add")
    if os.path.isdir(add_dir):
        for root, dirs, files in os.walk(add_dir):
            rel = os.path.relpath(root, add_dir)
            if rel != ".":
                add_with_parents(rel.replace(os.sep, "/"))
            for name in files:
                r = name if rel == "." else os.path.join(rel, name)
                add_with_parents(r.replace(os.sep, "/"))

    del_file = os.path.join(spec, "del.txt")
    if os.path.isfile(del_file):
        with open(del_file, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if not line.startswith("/"):
                    raise SystemExit("ERROR: del.txt 路径必须是镜像内绝对路径: %r" % line)
                add_with_parents(os.path.dirname(line))

    rc_dir = os.path.join(spec, "rc")
    if os.path.isdir(rc_dir):
        for root, dirs, files in os.walk(rc_dir):
            rel = os.path.relpath(root, rc_dir)
            for name in files:
                r = name if rel == "." else os.path.join(rel, name)
                add_with_parents(r.replace(os.sep, "/"))

    return sorted(paths, key=lambda p: (p.count("/"), p))


STAT_RE = {
    "ino": re.compile(r"Inode:\s*(\d+)"),
    "gen": re.compile(r"Generation:\s*(\d+)"),
    "ver": re.compile(r"Version:\s*0x([0-9a-fA-F]+):([0-9a-fA-F]+)"),
    "mode": re.compile(r"Mode:\s*0?([0-7]+)"),
    "size": re.compile(r"Size:\s*(\d+)"),
    "extra": re.compile(r"Size of extra inode fields:\s*(\d+)"),
    "time": re.compile(r"(atime|ctime|mtime|crtime):\s*0x([0-9a-fA-F]+)(?::([0-9a-fA-F]+))?"),
}


def debugfs_stat(img, path):
    try:
        out = subprocess.check_output(
            ["debugfs", "-R", "stat %s" % path, img],
            stderr=subprocess.DEVNULL).decode("utf-8", "replace")
    except subprocess.CalledProcessError:
        return None
    if "Inode:" not in out and "Inode:" not in out:
        return None
    m = STAT_RE["ino"].search(out)
    if not m:
        return None
    ent = {"ino": int(m.group(1))}
    m = STAT_RE["gen"].search(out)
    if not m:
        return None
    ent["generation"] = int(m.group(1))
    m = STAT_RE["mode"].search(out)
    if m:
        ent["mode"] = int(m.group(1), 8)
    m = STAT_RE["size"].search(out)
    if m:
        ent["size"] = int(m.group(1))
    m = STAT_RE["extra"].search(out)
    if m:
        ent["extra_isize"] = int(m.group(1))
    m = STAT_RE["ver"].search(out)
    if m:
        ent["version"] = [int(m.group(1), 16), int(m.group(2), 16)]
    for tm in STAT_RE["time"].finditer(out):
        name, sec, extra = tm.group(1), tm.group(2), tm.group(3)
        ent[name] = [int(sec, 16), int(extra, 16) if extra else 0]
    if not all(k in ent for k in ("atime", "ctime", "mtime", "crtime")):
        # crtime 可能缺失（extra_isize 太小时不打印），此时明确报错而不是猜
        return ent
    return ent


def main(argv):
    want_sha = "--sha256" in argv
    args = [a for a in argv[1:] if a != "--sha256"]
    out = None
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    if len(args) != 2:
        sys.stderr.write(__doc__)
        return 2
    ref_img, spec = args[0], args[1].rstrip("/")
    if not os.path.isfile(ref_img):
        raise SystemExit("ERROR: 参考镜像不存在: %s" % ref_img)
    if not os.path.isdir(spec):
        raise SystemExit("ERROR: SPEC_DIR 不存在: %s" % spec)
    out = out or os.path.join(spec, "meta.json")

    paths = parse_spec_paths(spec)
    print("[cap_meta] REF=%s" % ref_img)
    print("[cap_meta] SPEC=%s  推导路径 %d 个" % (spec, len(paths)))

    with open(ref_img, "rb") as f:
        sb = read_at(f, 1024, 1024)
        if struct.unpack_from("<H", sb, 0x38)[0] != 0xEF53:
            raise SystemExit("ERROR: 参考镜像不是 ext2/3/4")
        log_bs = struct.unpack_from("<I", sb, 0x18)[0]
        bs = 1024 << log_bs
        first_data_block = struct.unpack_from("<I", sb, 0x14)[0]
        blocks_count = struct.unpack_from("<I", sb, 0x04)[0]
        bpg = struct.unpack_from("<I", sb, 0x20)[0]
        ipg = struct.unpack_from("<I", sb, 0x28)[0]
        inode_size = struct.unpack_from("<H", sb, 0x58)[0]
        incompat = struct.unpack_from("<I", sb, 0x60)[0]
        ro_compat = struct.unpack_from("<I", sb, 0x64)[0]
        uuid = sb[0x68:0x78]
        desc_size = struct.unpack_from("<H", sb, 0xFE)[0] if incompat & 0x0080 else 32
        ngroups = (blocks_count + bpg - 1) // bpg
        gdt_off = (first_data_block + 1) * bs
        gdt = read_at(f, gdt_off, ngroups * desc_size)
        if ro_compat & 0x0200:
            raise SystemExit("ERROR: 参考镜像带 metadata_csum，本工具暂不支持")
        if not (ro_compat & 0x0010):
            print("[cap_meta] WARN: 无 GDT_CSUM(uninit_bg)，GDT 校验和按 0 处理")
        gdt_flags = []
        for g in range(ngroups):
            d = gdt[g * desc_size:(g + 1) * desc_size]
            gdt_flags.append(struct.unpack_from("<H", d, 0x12)[0])
        super_meta = {
            "mtime": struct.unpack_from("<I", sb, 0x2C)[0],
            "wtime": struct.unpack_from("<I", sb, 0x30)[0],
            "lastcheck": struct.unpack_from("<I", sb, 0x40)[0],
            "last_mounted": sb[0x88:0xC8].split(b"\x00")[0].decode("utf-8", "replace"),
            "kbytes_written": struct.unpack_from("<Q", sb, 0x178)[0],
        }

    inodes = {}
    missing = []
    # 读 inode 原始字节需要 inode table 位置（GDT 里 bg_inode_table_lo）
    itable = {}
    ipg = struct.unpack_from("<I", sb, 0x28)[0]
    for g in range(ngroups):
        d = gdt[g * desc_size:(g + 1) * desc_size]
        itable[g] = struct.unpack_from("<I", d, 0x08)[0]
    with open(ref_img, "rb") as f2:
        for p in paths:
            ent = debugfs_stat(ref_img, p)
            if ent is None:
                missing.append(p)
                continue
            if not all(k in ent for k in ("atime", "ctime", "mtime", "crtime", "generation")):
                raise SystemExit("ERROR: %s 元数据不完整（缺 crtime/extra）: %r" % (p, ent))
            ino = ent["ino"]
            g = (ino - 1) // ipg
            idx = (ino - 1) % ipg
            if g not in itable:
                raise SystemExit("ERROR: inode %d 组号 %d 越界" % (ino, g))
            ent["raw_inode"] = read_at(f2, itable[g] * bs + idx * inode_size,
                                       inode_size).hex()
            inodes[p] = ent
    if missing:
        print("[cap_meta] WARN: 参考镜像中不存在的路径（跳过）: %s" % missing)

    meta = {
        "generated_by": "srv_cap_meta.py",
        "ref_img": ref_img,
        "ref_size": os.path.getsize(ref_img),
        "bs": bs,
        "blocks_per_group": bpg,
        "inodes_per_group": ipg,
        "inode_size": inode_size,
        "ngroups": ngroups,
        "super": super_meta,
        "gdt_flags": gdt_flags,
        "inodes": inodes,
    }
    if want_sha:
        import hashlib
        h = hashlib.sha256()
        with open(ref_img, "rb") as f:
            while True:
                b = f.read(8 << 20)
                if not b:
                    break
                h.update(b)
        meta["ref_sha256"] = h.hexdigest()
        print("[cap_meta] ref sha256 = %s" % meta["ref_sha256"])

    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, out)
    print("[cap_meta] 写出 %s（inode 条目 %d，GDT 组 %d）" % (out, len(inodes), ngroups))
    print("[cap_meta] super: %r" % super_meta)
    print("[cap_meta] gdt_flags: %s" % gdt_flags)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

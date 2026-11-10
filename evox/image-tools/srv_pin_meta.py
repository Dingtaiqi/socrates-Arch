#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
srv_pin_meta.py — 把 meta.json 里记录的 ext4 元数据钉扎（patch）到镜像里。

用法:
    python3 srv_pin_meta.py <IMG> <META_JSON> [--dry-run]

meta.json（由 srv_cap_meta.py 从参考镜像捕获）:
{
  "blocks_per_group": 32768, "inodes_per_group": 368, "inode_size": 256,
  "super": {"mtime": int, "wtime": int, "lastcheck": int,
            "last_mounted": "/mnt/b42", "kbytes_written": int},
  "gdt_flags": [int, ...],           # 每个 block group 的 bg_flags
  "inodes": {"/path/in/image": {"ino": int, "mode": int, "size": int,
             "generation": int,
             "atime": [sec, extra_raw], "ctime": [...],
             "mtime": [...], "crtime": [...]}}
}

原理: ext4 在创建 inode 时 i_generation 取随机数、atime/ctime/mtime/crtime
取当前时间，所以"mount+cp"重放出的镜像内容相同但元数据不同；本脚本离线
直接改写 inode/超级块/GDT 字节，并重算 GDT 的 crc16 校验和，使原始镜像
sha256 可以逐字节复现（用于已知 base 镜像的可复现重建）。
"""
import json
import os
import struct
import sys

EXT4_BG_INODE_ZEROED = 0x0004
RO_COMPAT_GDT_CSUM = 0x0010
RO_COMPAT_METADATA_CSUM = 0x0200
INCOMPAT_64BIT = 0x0080


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


class Image(object):
    def __init__(self, path, writable=False):
        self.path = path
        self.f = open(path, "r+b" if writable else "rb")
        sb = self.read(1024, 1024)
        if struct.unpack_from("<H", sb, 0x38)[0] != 0xEF53:
            raise SystemExit("ERROR: %s 不是 ext2/3/4 镜像（magic 不符）" % path)
        self.log_block_size = struct.unpack_from("<I", sb, 0x18)[0]
        self.bs = 1024 << self.log_block_size
        self.first_data_block = struct.unpack_from("<I", sb, 0x14)[0]
        self.blocks_count = struct.unpack_from("<I", sb, 0x04)[0]
        self.blocks_per_group = struct.unpack_from("<I", sb, 0x20)[0]
        self.inodes_per_group = struct.unpack_from("<I", sb, 0x28)[0]
        self.inode_size = struct.unpack_from("<H", sb, 0x58)[0]
        self.feature_incompat = struct.unpack_from("<I", sb, 0x60)[0]
        self.feature_ro_compat = struct.unpack_from("<I", sb, 0x64)[0]
        self.uuid = sb[0x68:0x78]
        self.sb = sb
        self.desc_size = struct.unpack_from("<H", sb, 0xFE)[0] \
            if self.feature_incompat & INCOMPAT_64BIT else 32
        self.gdt_off = (self.first_data_block + 1) * self.bs
        self.ngroups = (self.blocks_count + self.blocks_per_group - 1) // self.blocks_per_group
        self.gdt = bytearray(self.read(self.gdt_off, self.ngroups * self.desc_size))

    def close(self):
        self.f.close()

    def read(self, off, n):
        self.f.seek(off)
        buf = b""
        while len(buf) < n:
            c = self.f.read(n - len(buf))
            if not c:
                break
            buf += c
        return buf

    def write(self, off, data):
        self.f.seek(off)
        self.f.write(data)

    # ---- 超级块 ----
    def patch_super(self, sup):
        changed = []
        sb_off = 1024
        for name, off, fmt in (("mtime", 0x2C, "<I"), ("wtime", 0x30, "<I"),
                               ("lastcheck", 0x40, "<I")):
            if name in sup:
                cur = struct.unpack_from(fmt, self.sb, off)[0]
                if cur != sup[name]:
                    self.write(sb_off + off, struct.pack(fmt, sup[name]))
                    changed.append("%s %d->%d" % (name, cur, sup[name]))
        if "last_mounted" in sup:
            raw = sup["last_mounted"].encode()[:63]
            raw = raw + b"\x00" * (64 - len(raw))
            cur = self.sb[0x88:0xC8]
            if cur != raw:
                self.write(sb_off + 0x88, raw)
                changed.append("last_mounted %r->%r" % (
                    cur.split(b"\x00")[0], sup["last_mounted"][:63]))
        if "kbytes_written" in sup:
            cur = struct.unpack_from("<Q", self.sb, 0x178)[0]
            if cur != sup["kbytes_written"]:
                self.write(sb_off + 0x178, struct.pack("<Q", sup["kbytes_written"]))
                changed.append("kbytes %d->%d" % (cur, sup["kbytes_written"]))
        return changed

    # ---- 组描述符 ----
    def group_desc(self, g):
        o = g * self.desc_size
        return o, self.gdt[o:o + self.desc_size]

    def gdt_csum_ok(self):
        """验证本文件的 crc16 与镜像中已存的 bg_checksum 全部一致。"""
        if not (self.feature_ro_compat & RO_COMPAT_GDT_CSUM):
            return None, "no GDT_CSUM"
        if self.feature_ro_compat & RO_COMPAT_METADATA_CSUM:
            return None, "metadata_csum（本工具未实现 crc32c 组描述符校验）"
        ok = 0
        for g in range(self.ngroups):
            _, d = self.group_desc(g)
            stored = struct.unpack_from("<H", d, 0x1E)[0]
            crc = crc16(self.uuid)
            crc = crc16(struct.pack("<I", g), crc)
            crc = crc16(bytes(d[0:0x1E]), crc)
            if crc == stored:
                ok += 1
        return ok, "%d/%d" % (ok, self.ngroups)

    def patch_gdt_flags(self, flags):
        changed = []
        csum_note = ""
        if self.feature_ro_compat & RO_COMPAT_METADATA_CSUM:
            raise SystemExit("ERROR: 镜像带 metadata_csum，暂不支持改写 GDT/inode 校验和")
        for g, want in enumerate(flags):
            if g >= self.ngroups:
                break
            o, d = self.group_desc(g)
            cur = struct.unpack_from("<H", d, 0x12)[0]
            if cur == want:
                continue
            d = bytearray(d)
            struct.pack_into("<H", d, 0x12, want)
            # 重算 bg_checksum (crc16 over uuid + group + desc[0:0x1e])
            crc = crc16(self.uuid)
            crc = crc16(struct.pack("<I", g), crc)
            crc = crc16(bytes(d[0:0x1E]), crc)
            struct.pack_into("<H", d, 0x1E, crc)
            self.write(self.gdt_off + o, d)
            changed.append("g%d flags 0x%x->0x%x" % (g, cur, want))
        return changed

    # ---- inode ----
    def inode_off(self, ino):
        g = (ino - 1) // self.inodes_per_group
        idx = (ino - 1) % self.inodes_per_group
        _, d = self.group_desc(g)
        itable = struct.unpack_from("<I", d, 0x08)[0]
        return itable * self.bs + idx * self.inode_size

    def inode_raw(self, ino):
        n = self.inode_size
        return bytearray(self.read(self.inode_off(ino), n))

    def patch_inode(self, ino, meta):
        off = self.inode_off(ino)
        cur = self.inode_raw(ino)
        mode = struct.unpack_from("<H", cur, 0x00)[0]
        size_lo = struct.unpack_from("<I", cur, 0x04)[0]
        size_hi = struct.unpack_from("<I", cur, 0x6C)[0]
        if "mode" in meta and meta["mode"] is not None and (mode & 0o7777) != (meta["mode"] & 0o7777):
            raise SystemExit("ERROR: inode %d mode 不符（当前 0%o != meta 0%o）" % (ino, mode & 0o7777, meta["mode"] & 0o7777))
        if "size" in meta and meta["size"] is not None:
            cur_size = size_lo | (size_hi << 32)
            if cur_size != meta["size"]:
                raise SystemExit("ERROR: inode %d size 不符（当前 %d != meta %d）" % (ino, cur_size, meta["size"]))
        extra_isize = struct.unpack_from("<H", cur, 0x80)[0]
        if extra_isize < 32:
            raise SystemExit("ERROR: inode %d extra_isize=%d < 32，无法写 nsec/crtime 字段" % (ino, extra_isize))
        changed = []
        for name, sec_off, extra_off in (("atime", 0x08, 0x8C),
                                         ("ctime", 0x0C, 0x84),
                                         ("mtime", 0x10, 0x88),
                                         ("crtime", 0x90, 0x94)):
            if name not in meta:
                continue
            sec, extra = meta[name]
            c_sec = struct.unpack_from("<I", cur, sec_off)[0]
            c_extra = struct.unpack_from("<I", cur, extra_off)[0]
            if c_sec != sec:
                changed.append("%s.sec %d->%d" % (name, c_sec, sec))
                struct.pack_into("<I", cur, sec_off, sec)
            if c_extra != extra:
                changed.append("%s.extra 0x%x->0x%x" % (name, c_extra, extra))
                struct.pack_into("<I", cur, extra_off, extra)
        if "generation" in meta:
            c_gen = struct.unpack_from("<I", cur, 0x64)[0]
            if c_gen != meta["generation"]:
                changed.append("generation %d->%d" % (c_gen, meta["generation"]))
                struct.pack_into("<I", cur, 0x64, meta["generation"])
        raw = meta.get("raw_inode")
        if raw:
            # 参考镜像里该 inode 的完整 256 字节。只允许"无法确定性重放"的
            # 字节不同（时间戳/version(osd1)/generation/extra 区），其余字节
            # （mode/uid/gid/size/links/flags/i_blocks/i_block 等语义字段）
            # 必须完全一致，否则视为内容结构不一致，直接报错而不是掩盖。
            ref = bytes.fromhex(raw)
            if len(ref) != len(cur):
                raise SystemExit("ERROR: inode %d raw_inode 长度 %d != %d"
                                 % (ino, len(ref), len(cur)))
            allowed = [(0x08, 0x18), (0x24, 0x28), (0x64, 0x68), (0x80, 0xA0)]
            # i_block 里"当前 extent 树实际使用长度之后"的字节是内核复用 inode
            # 留下的残留（extent 合并/删除时的移位），无法确定性重放，也允许覆盖；
            # 使用中的部分（extent 头 + entries 项）必须与参考一致。
            flags = struct.unpack_from("<I", cur, 0x20)[0]
            if flags & 0x00080000:  # EXT4_EXTENTS_FL
                if cur[0x28:0x2A] == b"\x0a\xf3":
                    entries = struct.unpack_from("<H", cur, 0x2A)[0]
                    used = min(12 + entries * 12, 60)
                    if used < 60:
                        allowed.append((0x28 + used, 0x64))
            def pinnable(i):
                return any(lo <= i < hi for lo, hi in allowed)
            bad = [i for i in range(len(ref)) if not pinnable(i) and ref[i] != cur[i]]
            if bad:
                raise SystemExit("ERROR: inode %d 语义字段与参考不一致（offset %s），"
                                 "拒绝按参考字节覆盖" % (ino, ["0x%x" % b for b in bad[:12]]))
            if bytes(cur) != ref:
                changed.append("raw inode bytes（时间/version/残留字段）")
            cur = bytearray(ref)
        if changed:
            self.write(off, bytes(cur))
        return changed


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv[1:] if a != "--dry-run"]
    if len(args) != 2:
        sys.stderr.write(__doc__)
        return 2
    img_path, meta_path = args
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    img = Image(img_path, writable=not dry)

    print("[pin_meta] IMG=%s META=%s dry_run=%s" % (img_path, meta_path, dry))
    print("[pin_meta] bs=%d bpg=%d ipg=%d inode_size=%d groups=%d desc=%d"
          % (img.bs, img.blocks_per_group, img.inodes_per_group,
             img.inode_size, img.ngroups, img.desc_size))

    ok, note = img.gdt_csum_ok()
    if ok is None:
        print("[pin_meta] GDT csum: %s（跳过校验）" % note)
    elif ok != img.ngroups:
        raise SystemExit("ERROR: GDT crc16 自校验失败 %s，拒绝改写（算法不符）" % note)
    else:
        print("[pin_meta] GDT crc16 自校验通过 %s" % note)

    n_sb = 0
    if "super" in meta:
        ch = img.patch_super(meta["super"])
        n_sb = len(ch)
        for c in ch:
            print("[pin_meta]   SB  %s" % c)
    n_gdt = 0
    if "gdt_flags" in meta:
        ch = img.patch_gdt_flags(meta["gdt_flags"])
        n_gdt = len(ch)
        for c in ch:
            print("[pin_meta]   GDT %s" % c)
    n_ino = 0
    n_field = 0
    for path in sorted(meta.get("inodes", {})):
        ent = meta["inodes"][path]
        if "ino" not in ent:
            raise SystemExit("ERROR: meta 中 %s 缺少 ino" % path)
        ch = img.patch_inode(ent["ino"], ent)
        if ch:
            n_ino += 1
            n_field += len(ch)
            print("[pin_meta]   INO %d %s: %s" % (ent["ino"], path, "; ".join(ch)))
    print("[pin_meta] 完成: super 字段 %d, GDT 组 %d, inode %d 个（%d 字段）%s"
          % (n_sb, n_gdt, n_ino, n_field, "（dry-run 未写入）" if dry else ""))
    img.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

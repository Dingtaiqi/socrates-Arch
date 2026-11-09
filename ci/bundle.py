"""Hash-checked, split gzip image archives. Python standard library only."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

CHUNK = 4 * 1024 * 1024
PART_SIZE = 1024 ** 3  # Each GitHub Release asset must be smaller than 2 GiB.
ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def basename(name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
        raise ValueError("Unsafe asset name")
    return name


class Parts:
    def __init__(self, directory, prefix, limit):
        if not 0 < limit < 2 * 1024 ** 3:
            raise ValueError("Invalid part size")
        self.directory, self.prefix, self.limit = directory, prefix, limit
        self.file = None
        self.entries = []

    def write(self, data):
        original = len(data)
        while data:
            if self.file is None:
                self.name = f"{self.prefix}.part{len(self.entries):03d}"
                self.file = (self.directory / self.name).open("xb")
                self.size, self.hash = 0, hashlib.sha256()
            block = data[:self.limit - self.size]
            self.file.write(block)
            self.hash.update(block)
            self.size += len(block)
            data = data[len(block):]
            if self.size == self.limit:
                self.close()
        return original

    def flush(self):
        if self.file:
            self.file.flush()

    def close(self):
        if self.file:
            self.file.close()
            self.entries.append(dict(name=self.name, bytes=self.size,
                                     sha256=self.hash.hexdigest()))
            self.file = None


def pack(source, directory, name, expected=None, part_size=PART_SIZE):
    source, directory = Path(source), Path(directory)
    basename(name)
    directory.mkdir(parents=True, exist_ok=True)
    manifest_path = directory / f"{name}.manifest.json"
    if manifest_path.exists():
        raise FileExistsError(manifest_path)
    h, size = hashlib.sha256(), 0
    parts = Parts(directory, name + ".gz", part_size)
    try:
        with source.open("rb") as src, gzip.GzipFile(
                filename="", mode="wb", fileobj=parts, compresslevel=1, mtime=0) as gz:
            for block in iter(lambda: src.read(CHUNK), b""):
                h.update(block)
                size += len(block)
                gz.write(block)
    finally:
        parts.close()
    if expected and (size != expected["bytes"] or h.hexdigest() != expected["sha256"]):
        raise ValueError(f"Baseline mismatch: {name}; no manifest created")
    manifest = dict(schema=1, name=name, bytes=size, sha256=h.hexdigest(),
                    compression="gzip", parts=parts.entries)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"PACKED {name}: {size} bytes SHA256={h.hexdigest()}", flush=True)
    return manifest_path


def restore(manifest_path, output, expected=None):
    manifest_path, output = Path(manifest_path), Path(output)
    m = json.loads(manifest_path.read_text(encoding="utf-8"))
    if m.get("schema") != 1 or m.get("compression") != "gzip":
        raise ValueError("Unsupported manifest")
    basename(m["name"])
    if expected and any(m[k] != expected[k] for k in ("name", "bytes", "sha256")):
        raise ValueError("Manifest does not match pinned baseline")
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if not m["parts"] or len({p["name"] for p in m["parts"]}) != len(m["parts"]):
        raise ValueError("Empty or duplicate part list")
    temporary = output.with_name(output.name + ".partial")
    if temporary.exists():
        raise FileExistsError(temporary)
    # The joined gzip is temporary and removed on both success and failure.
    with tempfile.TemporaryFile(dir=output.parent) as compressed:
        for p in m["parts"]:
            path = manifest_path.parent / basename(p["name"])
            if path.stat().st_size != p["bytes"] or digest(path) != p["sha256"]:
                raise ValueError(f"Corrupt/missing part: {p['name']}")
            with path.open("rb") as src:
                shutil.copyfileobj(src, compressed, CHUNK)
        compressed.seek(0)
        h, size = hashlib.sha256(), 0
        try:
            with gzip.GzipFile(fileobj=compressed, mode="rb") as gz, temporary.open("xb") as dst:
                for block in iter(lambda: gz.read(CHUNK), b""):
                    size += len(block)
                    if size > m["bytes"]:
                        raise ValueError("Expanded image exceeds declared size")
                    h.update(block)
                    dst.write(block)
            if size != m["bytes"] or h.hexdigest() != m["sha256"]:
                raise ValueError("Restored image checksum mismatch")
            temporary.rename(output)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"RESTORED {m['name']}: SHA256={h.hexdigest()}", flush=True)


def fetch(kind, output):
    config = json.loads((ROOT / "ci/baselines.json").read_text())
    item = config[kind]
    repo = os.environ["GITHUB_REPOSITORY"]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        subprocess.run(["gh", "release", "download", config["seed_release"],
                        "--repo", repo, "--pattern", item["name"] + ".*",
                        "--dir", tmp], check=True)
        restore(Path(tmp) / (item["name"] + ".manifest.json"), output, item)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    prepare = sub.add_parser("prepare-seeds")
    prepare.add_argument("workspace", type=Path)
    prepare.add_argument("output", type=Path)
    get = sub.add_parser("fetch")
    get.add_argument("kind", choices=["arch", "evox"])
    get.add_argument("output", type=Path)
    archive = sub.add_parser("pack")
    archive.add_argument("image", type=Path)
    archive.add_argument("output", type=Path)
    archive.add_argument("--name", required=True)
    unpack = sub.add_parser("restore")
    unpack.add_argument("manifest", type=Path)
    unpack.add_argument("output", type=Path)
    args = p.parse_args()
    if args.command == "prepare-seeds":
        config = json.loads((ROOT / "ci/baselines.json").read_text())
        for kind in ("evox", "arch"):
            item = config[kind]
            target = args.output / (item["name"] + ".manifest.json")
            if target.exists():
                m = json.loads(target.read_text())
                if any(m[k] != item[k] for k in ("name", "bytes", "sha256")):
                    raise ValueError("Existing seed manifest differs")
                for part in m["parts"]:
                    path = args.output / basename(part["name"])
                    if path.stat().st_size != part["bytes"] or digest(path) != part["sha256"]:
                        raise ValueError("Existing seed part differs")
                print(f"SEED ALREADY VERIFIED {kind}", flush=True)
            else:
                pack(args.workspace / item["local"], args.output, item["name"], item,
                     part_size=64 * 1024 * 1024)
    elif args.command == "fetch":
        fetch(args.kind, args.output)
    elif args.command == "pack":
        pack(args.image, args.output, args.name)
    else:
        restore(args.manifest, args.output)


if __name__ == "__main__":
    main()

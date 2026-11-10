#!/usr/bin/env python3
"""Restore the compiler/sysroot kit used by the portable Turnip recipe."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile

spec = importlib.util.spec_from_file_location('source_restore', Path(__file__).resolve().parents[1] / 'evox/restore-source.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('build-inputs.json'))
parser.add_argument('--archive', type=Path, help='Use an existing server-local archive without downloading')
args = parser.parse_args()
if not args.manifest.is_file():
    raise SystemExit('Build input migration has not published its index yet')
record = json.loads(args.manifest.read_text())
root = args.destination.resolve()
identity = hashlib.sha256(args.manifest.read_bytes()).hexdigest()
marker = root / 'RESTORED_INPUTS.json'
if marker.exists():
    if json.loads(marker.read_text())['manifest_sha256'] != identity:
        raise SystemExit('Existing directory belongs to another input snapshot')
    print('ARCH_INPUTS_ALREADY_RESTORED', root / 'inputs')
    raise SystemExit(0)
if root.exists() and any(root.iterdir()):
    raise SystemExit('Destination must be empty')
root.mkdir(parents=True, exist_ok=True)
item, = record['assets']
archive = args.archive or root / item['name']
if not args.archive:
    restore.download('https://github.com/Dingtaiqi/socrates-Arch/releases/download/' + record['release_tag'] + '/' + item['name'], archive, item)
restore.verify_parts([archive], {'parts': [item], 'sha256': item['sha256']})
with tempfile.TemporaryDirectory(dir=root) as temp:
    with archive.open('rb') as stream:
        restore.extract(stream, Path(temp))
    shutil.move(temp, root / 'inputs')
marker.write_text(json.dumps({'manifest_sha256': identity, 'coverage': record['coverage']}, indent=2) + '\n')
if not args.archive:
    archive.unlink()
print('ARCH_INPUTS_RESTORED', root / 'inputs')

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
parser.add_argument('--local-assets', type=Path, help='Use existing server-local assets without downloading')
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
pending = root / 'RESTORING_INPUTS.json'
if root.exists() and any(root.iterdir()) and not pending.exists():
    raise SystemExit('Destination must be empty')
root.mkdir(parents=True, exist_ok=True)
if pending.exists() and json.loads(pending.read_text())['manifest_sha256'] != identity:
    raise SystemExit('Partial input restoration belongs to another snapshot')
pending.write_text(json.dumps({'manifest_sha256': identity}))
with tempfile.TemporaryDirectory(dir=root) as temp:
    for item in record['assets']:
        archive = restore.safe_path((args.local_assets or root).resolve(), item['name'])
        if not args.local_assets:
            restore.download('https://github.com/Dingtaiqi/socrates-Arch/releases/download/' + record['release_tag'] + '/' + item['name'], archive, item)
        restore.verify_parts([archive], {'parts': [item], 'sha256': item['sha256']})
        if item.get('kind', 'tar') == 'file':
            target = restore.safe_path(Path(temp), item['destination'])
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(archive, target)
        else:
            with archive.open('rb') as stream:
                restore.extract(stream, Path(temp))
        if not args.local_assets:
            archive.unlink()
    shutil.move(temp, root / 'inputs')
marker.write_text(json.dumps({'manifest_sha256': identity, 'coverage': record['coverage']}, indent=2) + '\n')
pending.unlink()
print('ARCH_INPUTS_RESTORED', root / 'inputs')

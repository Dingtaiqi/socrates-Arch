#!/usr/bin/env python3
"""Build native init in the public, fixed Arch distro base; no phone access."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

restore = load('source_restore', repo / 'evox/restore-source.py')
bundle = load('image_bundle', repo / 'ci/bundle.py')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
index = repo / 'arch/build-base.json'
if not index.is_file():
    raise SystemExit('The public Arch base has not been published yet')
record = json.loads(index.read_text())
image = args.output.resolve()
if image.exists():
    raise SystemExit('Output already exists')
image.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='arch-base-', dir=image.parent) as temp:
    temp = Path(temp)
    prefix = 'https://github.com/Dingtaiqi/socrates-Arch/releases/download/' + record['release_tag'] + '/'
    manifest = temp / record['manifest']['name']
    restore.download(prefix + manifest.name, manifest, record['manifest'])
    restore.verify_parts([manifest], {'parts': [record['manifest']], 'sha256': record['manifest']['sha256']})
    image_record = json.loads(manifest.read_text())
    for part in image_record['parts']:
        restore.download(prefix + part['name'], temp / part['name'], part)
    bundle.restore(manifest, image, {'bytes': record['image_bytes'], 'sha256': record['image_sha256']})
environment = {**os.environ, 'EXPECTED_PERSIST_UUID': record['persist_uuid'],
               'EXPECTED_ROOTFS_SHA256': record['rootfs_sha256']}
subprocess.run(['bash', str(repo / 'ci/rebuild-arch.sh'), str(image)], cwd=repo, env=environment, check=True)
print('ARCH_IMAGE_BUILT', image)

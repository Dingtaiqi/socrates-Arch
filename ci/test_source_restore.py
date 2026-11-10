"""A real Git checkout, local patch, manifest link, and interrupted restore."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

RESTORER = Path(__file__).resolve().parents[1] / 'evox/restore-source.py'


@unittest.skipIf(os.name == 'nt', 'Restoration targets Linux filesystems')
class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'original'
        self.source.mkdir()
        self.git('init', '-q')
        (self.source / 'hello.txt').write_text('upstream\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        head = self.git('rev-parse', 'HEAD').decode().strip()
        ident = hashlib.sha256(b'platform/demo').hexdigest()[:20]
        self.project = {'path': 'platform/demo', 'id': ident, 'head': head, 'kind': 'project', 'lfs_objects': 0}
        mirror = self.root / 'mirrors' / (ident + '.git')
        subprocess.run(['git', 'clone', '--bare', '--no-local', '--depth', '1', self.source.as_uri(), str(mirror)],
                       check=True, capture_output=True)
        (self.source / 'hello.txt').write_text('local porting fix\n')
        capture = self.root / 'server-sources'
        project = capture / 'projects' / ident
        (project / 'files').mkdir(parents=True)
        (project / 'tracked.patch').write_bytes(self.git('diff', '--binary', 'HEAD'))
        (project / 'files' / 'new.conf').write_text('feature=1\n')
        files = [{'path': 'new.conf', 'sha256': hashlib.sha256(b'feature=1\n').hexdigest()}]
        (capture / 'projects.json').write_text(json.dumps([{**self.project, 'files': files}]))
        overlay = self.root / 'overlay.tar.gz'
        with tarfile.open(overlay, 'w:gz') as archive:
            archive.add(capture, arcname='server-sources')
        manifest = self.root / 'manifest.xml'
        manifest.write_text('<manifest><remote name="origin" fetch="https://example.invalid"/>'
                            '<default remote="origin"/><project name="fixture" path="platform/demo">'
                            '<copyfile src="hello.txt" dest="README.txt"/>'
                            '<linkfile src="hello.txt" dest="hello-link"/></project></manifest>')
        self.part = self.root / 'fixture.part0000'
        with tarfile.open(self.part, 'w:gz') as archive:
            archive.add(mirror, arcname='mirrors/' + ident + '.git')
            archive.add(overlay, arcname='meta/porting-overlay.tar.gz')
            archive.add(manifest, arcname='meta/manifest.lock.xml')
        digest = hashlib.sha256(self.part.read_bytes()).hexdigest()
        self.snapshot = self.root / 'snapshot.json'
        self.snapshot.write_text(json.dumps({'groups': [{'index': 0, 'sha256': digest,
            'projects': [self.project], 'parts': [{'name': self.part.name, 'bytes': self.part.stat().st_size,
                                                 'sha256': digest}]}]}))
        self.destination = self.root / 'restored'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source), *args], stderr=subprocess.PIPE)

    def restore(self):
        return subprocess.run([sys.executable, str(RESTORER), str(self.destination), '--manifest', str(self.snapshot),
                               '--local-parts', str(self.root)], capture_output=True, text=True)

    def test_restore_and_resume_preserve_source_patch_and_local_changes(self):
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / 'platform/demo/hello.txt').read_text(), 'local porting fix\n')
        self.assertEqual((self.destination / 'platform/demo/new.conf').read_text(), 'feature=1\n')
        self.assertEqual((self.destination / 'README.txt').read_text(), 'local porting fix\n')
        self.assertTrue((self.destination / 'hello-link').is_symlink())
        changed = self.destination / 'platform/demo/hello.txt'
        changed.write_text('later developer edit\n')
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(changed.read_text(), 'later developer edit\n')

    def test_corrupt_part_is_rejected_before_checkout(self):
        data = bytearray(self.part.read_bytes())
        data[len(data)//2] ^= 1
        self.part.write_bytes(data)
        result = self.restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum differs', result.stderr)
        self.assertFalse((self.destination / 'platform').exists())


if __name__ == '__main__':
    unittest.main()

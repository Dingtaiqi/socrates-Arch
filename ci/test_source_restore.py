"""A real Git checkout, local patch, manifest link, and interrupted restore."""
import hashlib
import json
import os
from pathlib import Path
import shutil
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
        self.mirror = self.root / 'mirrors' / (ident + '.git')
        subprocess.run(['git', 'clone', '--bare', '--no-local', '--depth', '1', self.source.as_uri(), str(self.mirror)],
                       check=True, capture_output=True)
        (self.source / 'hello.txt').write_text('local porting fix\n')
        capture = self.root / 'server-sources'
        project = capture / 'projects' / ident
        (project / 'files').mkdir(parents=True)
        (project / 'tracked.patch').write_bytes(self.git('diff', '--binary', 'HEAD'))
        (project / 'files' / 'new.conf').write_text('feature=1\n')
        files = [{'path': 'new.conf', 'sha256': hashlib.sha256(b'feature=1\n').hexdigest()}]
        (capture / 'projects.json').write_text(json.dumps([{**self.project, 'files': files}]))
        self.overlay = self.root / 'overlay.tar.gz'
        with tarfile.open(self.overlay, 'w:gz') as archive:
            archive.add(capture, arcname='server-sources')
        self.manifest = self.root / 'manifest.xml'
        self.manifest.write_text('<manifest><remote name="origin" fetch="https://example.invalid"/>'
                            '<default remote="origin"/><project name="fixture" path="platform/demo">'
                            '<copyfile src="hello.txt" dest="README.txt"/>'
                            '<linkfile src="hello.txt" dest="hello-link"/></project></manifest>')
        self.part = self.root / 'fixture.part0000'
        self.snapshot = self.root / 'snapshot.json'
        self.write_archive()
        self.destination = self.root / 'restored'

    def write_archive(self):
        with tarfile.open(self.part, 'w:gz') as archive:
            archive.add(self.mirror, arcname='mirrors/' + self.project['id'] + '.git')
            archive.add(self.overlay, arcname='meta/porting-overlay.tar.gz')
            archive.add(self.manifest, arcname='meta/manifest.lock.xml')
        digest = hashlib.sha256(self.part.read_bytes()).hexdigest()
        self.snapshot.write_text(json.dumps({'groups': [{'index': 0, 'sha256': digest,
            'projects': [self.project], 'parts': [{'name': self.part.name, 'bytes': self.part.stat().st_size,
                                                 'sha256': digest}]}]}))

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.source), *args], stderr=subprocess.PIPE)

    def restore(self, env=None):
        return subprocess.run([sys.executable, str(RESTORER), str(self.destination), '--manifest', str(self.snapshot),
                               '--local-parts', str(self.root)], capture_output=True, text=True, env=env)

    def test_lfs_uses_bundled_objects_without_global_filter_setup(self):
        self.assertIsNotNone(shutil.which('git-lfs'), 'The Linux check environment must install git-lfs')
        self.git('config', 'lfs.storage', 'lfs')
        self.git('lfs', 'install', '--local', '--force', '--skip-repo')
        payload = b'pinned-build-input\0' * 4096
        (self.source / '.gitattributes').write_text('*.bin filter=lfs diff=lfs merge=lfs -text\n')
        (self.source / 'artifact.bin').write_bytes(payload)
        literal = b'version https://git-lfs.github.com/spec/v1\noid sha256:' + b'a' * 64 + b'\nsize 999999\n'
        (self.source / 'literal-pointer.txt').write_bytes(literal)
        self.git('add', '.gitattributes', 'artifact.bin', 'literal-pointer.txt')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'LFS input')
        self.project.update(head=self.git('rev-parse', 'HEAD').decode().strip(), lfs_objects=1)
        shutil.rmtree(self.mirror)
        subprocess.run(['git', 'clone', '--bare', '--no-local', '--depth', '1', self.source.as_uri(), str(self.mirror)],
                       check=True, capture_output=True)
        oid = hashlib.sha256(payload).hexdigest()
        relative = Path('lfs/objects') / oid[:2] / oid[2:4] / oid
        target = self.mirror / relative
        target.parent.mkdir(parents=True)
        shutil.copyfile(self.source / '.git' / relative, target)
        self.write_archive()
        config = self.root / 'global.gitconfig'
        config.write_text('[lfs]\n\tstorage = ' + str(self.root / 'unrelated-global-storage') + '\n')
        result = self.restore({**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': str(config)})
        self.assertEqual(result.returncode, 0, result.stderr)
        restored = self.destination / 'platform/demo'
        self.assertEqual((restored / 'artifact.bin').read_bytes(), payload)
        self.assertEqual((restored / 'literal-pointer.txt').read_bytes(), literal)
        diff = subprocess.run(['git', '-C', str(restored), 'diff', '--exit-code', 'HEAD', '--', 'artifact.bin'],
                              capture_output=True)
        self.assertEqual(diff.returncode, 0, diff.stderr)

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

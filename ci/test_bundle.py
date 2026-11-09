import json
from pathlib import Path
import random
import tempfile
import unittest

from bundle import pack, restore, digest


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source.img'
        self.source.write_bytes(random.Random(42).randbytes(65536))
        self.manifest = pack(self.source, self.root / 'parts', 'test.img', part_size=4096)

    def test_multivolume_roundtrip(self):
        output = self.root / 'restored.img'
        restore(self.manifest, output)
        self.assertEqual(digest(self.source), digest(output))
        with self.assertRaises(FileExistsError):
            restore(self.manifest, output)

    def test_corruption_and_missing_part(self):
        part = self.manifest.parent / 'test.img.gz.part001'
        part.write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            restore(self.manifest, self.root / 'bad.img')
        self.assertFalse((self.root / 'bad.img').exists())
        part.unlink()
        with self.assertRaises(FileNotFoundError):
            restore(self.manifest, self.root / 'bad.img')

    def test_pinned_hash_and_path_validation(self):
        m = json.loads(self.manifest.read_text())
        pin = {k: m[k] for k in ('name', 'bytes', 'sha256')}
        pin['sha256'] = '0' * 64
        with self.assertRaises(ValueError):
            restore(self.manifest, self.root / 'bad.img', pin)
        m['parts'][0]['name'] = '../outside'
        self.manifest.write_text(json.dumps(m))
        with self.assertRaises(ValueError):
            restore(self.manifest, self.root / 'bad.img')

    def test_expanded_hash_mismatch(self):
        m = json.loads(self.manifest.read_text())
        m['sha256'] = '0' * 64
        self.manifest.write_text(json.dumps(m))
        with self.assertRaises(ValueError):
            restore(self.manifest, self.root / 'bad.img')
        self.assertFalse((self.root / 'bad.img.partial').exists())


if __name__ == '__main__':
    unittest.main()

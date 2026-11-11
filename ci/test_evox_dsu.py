"""Exercise the exact vendor filter and real ext4 metadata/readback operations."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('b66_compat',REPO/'evox/dsu/patch-b66.py')
compat=importlib.util.module_from_spec(spec);spec.loader.exec_module(compat)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.source=(REPO/'evox/dsu/stock/manifest_kalama.xml').read_bytes()

    def test_pinned_vendor_removes_only_absent_omx(self):
        self.assertEqual(hashlib.sha256(self.source).hexdigest(),
            '53a490b7612fc2ca90bf4de3cf027c0799826a558b70b848e1f539a667e42d00')
        result=compat.without_legacy_omx(self.source)
        self.assertEqual(hashlib.sha256(result).hexdigest(),
            '3479bbd1fc774f47a400e8bb563d351c7028e191f6fd95f459978fb4660c150e')
        self.assertNotIn(b'<name>android.hardware.media.omx</name>',result)
        # Other HALs in this file remain; separate Codec2 manifest fragments
        # are outside the patcher's three fixed destination paths.
        self.assertIn(b'<name>android.hardware.audio</name>',result)
        with self.assertRaises(ValueError):compat.without_legacy_omx(result)

    def test_unknown_omx_shape_is_rejected(self):
        changed=self.source.replace(b'<name>IOmxStore</name>',b'<name>OtherStore</name>')
        with self.assertRaises(ValueError):compat.without_legacy_omx(changed)

    def test_duplicate_watchdog_properties_are_replaced(self):
        result=compat.properties_with_watchdog(b'ro.example=keep\npersist.sys.dsu_watchdog=600\n'
            b'persist.sys.dsu_daily=1\npersist.sys.dsu_watchdog=1800\n')
        self.assertIn(b'ro.example=keep\n',result)
        self.assertEqual(result.count(b'persist.sys.dsu_watchdog='),1)
        self.assertTrue(result.endswith(b'persist.sys.dsu_watchdog=300\n'))
        with self.assertRaises(ValueError):compat.properties_with_watchdog(b'persist.sys.dsu_daily=0\n')


@unittest.skipUnless(sys.platform=='linux' and all(shutil.which(x) for x in
    ('mkfs.ext4','debugfs','e2fsck')),'Linux e2fsprogs required')
class Ext4Tests(unittest.TestCase):
    def test_real_payload_context_owner_and_pristine_input(self):
        with tempfile.TemporaryDirectory(prefix='ext4 fixture ') as directory:
            work=Path(directory);original=work/'original image.img'
            with original.open('wb') as stream:stream.truncate(32*1024*1024)
            subprocess.run(['mkfs.ext4','-q','-F',str(original)],check=True)
            def debug(command,image=original):
                return subprocess.run(['debugfs','-w','-R',command,str(image)],check=True,
                    stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True).stdout
            for name in ('/system','/system/etc','/system/etc/init'):debug('mkdir '+name)
            prop=work/'original prop';prop.write_bytes(b'ro.example=keep\npersist.sys.dsu_daily=1\n')
            label=work/'original label';label.write_bytes(b'u:object_r:system_file:s0\0')
            debug('write '+compat.quote_debugfs(prop)+' /system/build.prop')
            debug('ea_set -f '+compat.quote_debugfs(label)+' /system/build.prop security.selinux')
            original_sha=compat.sha256(original)
            patched=work/'patched image.img';shutil.copyfile(original,patched)
            payload_work=work/'payload work';payload_work.mkdir()
            source=(REPO/'evox/dsu/stock/manifest_kalama.xml').read_bytes()
            rc=(REPO/'evox/dsu/socrates-compat.rc').read_bytes()
            records=compat.patch_ext4(patched,payload_work,compat.without_legacy_omx(source),rc)
            self.assertEqual(compat.sha256(original),original_sha)
            self.assertEqual(len(records),3)
            for path in records:
                info=debug('stat '+compat.quote_debugfs(path),patched)
                self.assertRegex(info,r'Mode:\s+0644')
                self.assertRegex(info,r'User:\s+0\s+Group:\s+0')
            result=subprocess.run([sys.executable,str(REPO/'evox/dsu/patch-b66.py'),
                str(original),str(work/'invalid-seed-output.img')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('not the pinned b66',result.stderr)
            self.assertFalse((work/'invalid-seed-output.img').exists())


if __name__=='__main__':unittest.main()

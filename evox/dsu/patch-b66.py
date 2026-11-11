"""Apply the tested socrates runtime overlay to a copy of the pinned b66 image.

Linux and e2fsprogs required. Only regular image files are processed; this tool
has no ADB, fastboot, partition-writing or network operations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[1]


def sha256(path):
    result=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(8*1024*1024),b''):result.update(block)
    return result.hexdigest()


def without_legacy_omx(data):
    """Remove exactly the absent OMX HAL; preserve every other XML byte."""
    original=ET.fromstring(data)
    matches=[node for node in original.findall('hal')
             if node.findtext('name')=='android.hardware.media.omx']
    if len(matches)!=1:raise ValueError('Expected exactly one legacy OMX HAL')
    target=matches[0]
    if target.get('format')!='hidl':raise ValueError('Unexpected OMX transport')
    if {n.findtext('name') for n in target.findall('interface')}!={'IOmx','IOmxStore'}:
        raise ValueError('Unexpected OMX interfaces')
    removed=[]
    def keep(match):
        node=ET.fromstring(match.group().strip())
        if node.findtext('name')!='android.hardware.media.omx':return match.group()
        removed.append(node)
        return b''
    filtered=re.sub(rb'(?ms)^[ \t]*<hal\b[^>]*>.*?</hal>[ \t]*\r?\n',keep,data)
    if len(removed)!=1:raise ValueError('Could not isolate the OMX HAL')
    original.remove(target)
    def tree(node):
        return node.tag,sorted(node.attrib.items()),(node.text or '').strip(),[tree(n) for n in node]
    if tree(original)!=tree(ET.fromstring(filtered)):
        raise ValueError('Unrelated manifest content changed')
    return filtered


def properties_with_watchdog(data):
    daily=[line.split(b'=',1)[1] for line in data.splitlines()
           if line.startswith(b'persist.sys.dsu_daily=')]
    if not daily or daily[-1]!=b'1':raise ValueError('Expected b66 daily mode')
    lines=[line for line in data.splitlines(keepends=True)
           if not line.startswith(b'persist.sys.dsu_watchdog=')]
    return b''.join(lines).rstrip(b'\r\n')+b'\n\npersist.sys.dsu_watchdog=300\n'


def quote_debugfs(value):
    value=str(value)
    if any(c in value for c in '\r\n\0'):raise ValueError('Invalid debugfs path')
    return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'


def patch_ext4(image,work,manifest,rc):
    """Patch image metadata and verify every payload plus its SELinux attribute."""
    image=Path(image);work=Path(work)
    def debug(command,write=False):
        subprocess.run(['debugfs',*(['-w'] if write else []),'-R',command,str(image)],
                       check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    def extract(source,target):
        debug('dump '+quote_debugfs(source)+' '+quote_debugfs(target))
        return target.read_bytes()  # debugfs may return zero even on a failed command.
    props=properties_with_watchdog(extract('/system/build.prop',work/'original.prop'))
    label=work/'system-file.selinux'
    debug('ea_get -f '+quote_debugfs(label)+' /system/build.prop security.selinux')
    if label.read_bytes()!=b'u:object_r:system_file:s0\0':
        raise ValueError('Unexpected original build.prop SELinux context')
    files={'/system/build.prop':props,
           '/system/etc/init/zzzz_dsu_ksu_compat.rc':rc,
           '/system/etc/dsu-manifest-kalama-no-omx.xml':manifest}
    result={}
    for number,(destination,payload) in enumerate(files.items()):
        local=work/('payload-'+str(number));local.write_bytes(payload)
        if destination=='/system/build.prop':debug('rm '+quote_debugfs(destination),True)
        debug('write '+quote_debugfs(local)+' '+quote_debugfs(destination),True)
        debug('set_inode_field '+quote_debugfs(destination)+' mode 0100644',True)
        debug('set_inode_field '+quote_debugfs(destination)+' uid 0',True)
        debug('set_inode_field '+quote_debugfs(destination)+' gid 0',True)
        debug('ea_set -f '+quote_debugfs(label)+' '+quote_debugfs(destination)+' security.selinux',True)
        readback=work/('readback-'+str(number))
        if extract(destination,readback)!=payload:raise ValueError('Payload readback mismatch: '+destination)
        context=work/('context-'+str(number))
        debug('ea_get -f '+quote_debugfs(context)+' '+quote_debugfs(destination)+' security.selinux')
        if context.read_bytes()!=label.read_bytes():raise ValueError('SELinux readback mismatch')
        result[destination]={'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}
    subprocess.run(['e2fsck','-f','-n',str(image)],check=True)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path,help='Unmodified, pinned b66 raw image')
    parser.add_argument('output',type=Path,help='New output file; must not exist')
    args=parser.parse_args()
    if sys.platform!='linux':parser.error('Run on Linux with debugfs and e2fsck')
    for command in ('debugfs','e2fsck'):
        if not shutil.which(command):parser.error(command+' is required')
    source=args.input.resolve();output=args.output.absolute()
    if not source.is_file() or source.is_block_device():parser.error('A regular input image is required')
    if os.path.lexists(output) or os.path.lexists(str(output)+'.json'):
        parser.error('Refusing to overwrite an existing output or report')
    if not output.parent.is_dir():parser.error('Create the output directory first')
    baseline=json.loads((REPO/'ci/baselines.json').read_text())['evox']
    if source.stat().st_size!=baseline['bytes'] or sha256(source)!=baseline['sha256']:
        parser.error('Input is not the pinned b66 image')
    inputs=json.loads((HERE/'inputs.json').read_text())
    original=HERE/'stock/manifest_kalama.xml'
    if sha256(original)!=inputs['vendor_manifest_sha256']:raise ValueError('Stock manifest digest mismatch')
    manifest=without_legacy_omx(original.read_bytes())
    if hashlib.sha256(manifest).hexdigest()!=inputs['filtered_manifest_sha256']:
        raise ValueError('Filtered manifest digest mismatch')
    with tempfile.TemporaryDirectory(prefix='b66-compat-',dir=output.parent) as directory:
        work=Path(directory);image=work/'new.img'
        shutil.copyfile(source,image)
        patched=patch_ext4(image,work,manifest,(HERE/'socrates-compat.rc').read_bytes())
        report={'device':'socrates','source_sha256':baseline['sha256'],
                'bytes':image.stat().st_size,'sha256':sha256(image),'files':patched,
                'filesystem_check':'passed','phone_operations':False,'output_device_tested':False,
                'scope':'Runtime overlay on pinned b66; not a full ROM source build'}
        # Linking into the same directory fails atomically if another writer
        # created the requested output while this build was running.
        os.link(image,output)
    with Path(str(output)+'.json').open('x',encoding='utf-8') as stream:
        json.dump(report,stream,indent=2);stream.write('\n')
    print(json.dumps(report),flush=True)


if __name__=='__main__':main()

#!/usr/bin/env python3
"""Stage an isolated iOS SDK build. Never modifies source or enables production ads."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import zipfile

COMMIT = '615974e9f66921a54e3c71c33db0856bdbf19d13'
ZIP_SHA256 = '6e7f1c807761f9c0ad45d335ac4c74acd4bba7a31f9e1c7cd16a5220010cce71'
PREFIX = 'platforms/godot_editor/addons/admob/'

def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()

def stage(source, upstream, archive, destination):
    source, upstream, archive, destination = [Path(p).resolve() for p in (source, upstream, archive, destination)]
    if destination.exists() or source == destination or source in destination.parents:
        raise ValueError('Destination must be new and outside source project')
    if not (source/'project.godot').is_file():
        raise ValueError('Source must be Godot project folder')
    if git(upstream, 'rev-parse', 'HEAD') != COMMIT or git(upstream, 'status', '--porcelain'):
        raise ValueError('Upstream must be clean pinned Poing v5.1.0 commit')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ZIP_SHA256:
        raise ValueError('Native ZIP checksum mismatch; do not substitute engine versions')
    with zipfile.ZipFile(archive) as z:
        selected = [n for n in z.namelist() if n == 'package.gd' or n.startswith('ads/')]
        if '5.1.0' not in z.read('package.gd').decode():
            raise ValueError('Wrong native plugin version')
        for mode in ('debug', 'release'):
            info = plistlib.loads(z.read(f'ads/libs/poing-godot-admob-ads.{mode}.xcframework/Info.plist'))
            ids = {x['LibraryIdentifier'] for x in info['AvailableLibraries']}
            if ids != {'ios-arm64', 'ios-arm64_x86_64-simulator'}:
                raise ValueError('Unexpected native framework platforms')
        for n in selected:
            if PurePosixPath(n).is_absolute() or '..' in PurePosixPath(n).parts:
                raise ValueError('Unsafe archive path')
        shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.godot', '.DS_Store', 'build'))
        addon = destination/'addons/admob'
        addon.mkdir(parents=True, exist_ok=False)
        for name in git(upstream, 'ls-files', PREFIX).splitlines():
            src = upstream/name
            if src.is_file():
                dst = addon/name[len(PREFIX):]
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)
        native = addon/'ios/bin'
        for n in selected:
            target = native/n
            if n.endswith('/'):
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(n))
    entry = addon/'admob.gd'
    contents = entry.read_text()
    needle = '\tBinaryInstaller.install_missing_binaries_sync()'
    if contents.count(needle) != 1:
        raise ValueError('Upstream installer entry changed; inspect before activation')
    entry.write_text(contents.replace(needle, '\t# Nineweave staging: pinned iOS binaries supplied; no automatic downloads.'))
    project = destination/'project.godot'
    contents = project.read_text()
    if '[editor_plugins]' in contents or '[admob]' in contents:
        raise ValueError('Existing plugin configuration requires manual review')
    project.write_text(contents + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/admob/plugin.cfg")\n\n[admob]\ngeneral/ios/enabled=true\ngeneral/ios/app_id="ca-app-pub-3940256099942544~1458002511"\ngeneral/android/enabled=false\n')
    report = {'upstream_commit': COMMIT, 'native_zip_sha256': ZIP_SHA256,
              'godot': '4.7.2', 'plugin': '5.1.0', 'google_mobile_ads': '13.9.0',
              'google_ump': '3.1.0', 'test_app_id_only': True, 'mediation': False,
              'runtime_ads_enabled': False, 'signed': False,
              'upstream_patch': 'Disable auto-download in staged EditorPlugin only'}
    (destination/'NATIVE_STAGE.json').write_text(json.dumps(report, indent=2)+'\n')
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True)
    p.add_argument('--upstream', required=True)
    p.add_argument('--native-zip', required=True)
    p.add_argument('--destination', required=True)
    a = p.parse_args()
    print(json.dumps(stage(a.source, a.upstream, a.native_zip, a.destination), indent=2))

#!/usr/bin/env python3
"""Read-only native preparation check; not a signing or App Store submission tool."""
import argparse
import configparser
import json
import platform
from pathlib import Path
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--signing', action='store_true', help='also require Mac signing setup')
    parser.add_argument('--pack', type=Path, help='verify a Godot 4.7 native content PCK export')
    args = parser.parse_args()
    failures = []
    def check(condition, description):
        print(('PASS ' if condition else 'BLOCKED ') + description)
        if not condition:
            failures.append(description)
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(ROOT / 'export_presets.cfg')
    ios = next((s for s in cfg.sections() if cfg[s].get('platform') == '"iOS"'), None)
    check(ios is not None, 'iOS preset exists')
    if not ios:
        return 1
    value = lambda section, key: cfg[section].get(key, '').strip('"')
    check(value(ios, 'export_filter') == 'all_resources', 'iOS exports all resources')
    check('assets/hero_video/**/*.ogv' in value(ios, 'include_filter'), 'iOS bundles OGV clips')
    check('assets/hero_video/**/*.ogv' not in value(ios, 'exclude_filter'), 'iOS does not exclude clips')
    check('assets/hero_video/manifest.json' in value(ios, 'include_filter'), 'manifest bundled')
    options = ios + '.options'
    check(value(options, 'application/targeted_device_family') == '2', 'iPhone and iPad target')
    check(value(options, 'application/export_project_only') == 'true', 'project-only export; no upload')
    manifest = json.loads((ROOT / 'assets/hero_video/manifest.json').read_text())
    count = total = 0
    for hero, kinds in manifest.items():
        for kind in kinds:
            path = ROOT / 'assets/hero_video' / hero / f'{kind}.ogv'
            valid = path.is_file() and path.stat().st_size > 4
            if valid:
                with path.open('rb') as stream:
                    valid = stream.read(4) == b'OggS'
            check(valid, f'bundled media {hero}/{kind}')
            if valid:
                count += 1
                total += path.stat().st_size
    check(len(manifest) == 35 and count == 70, '35 heroes / 70 clips')
    print(f'INFO source media {total / 1024**2:.1f} MiB; not final app size')
    if args.pack:
        raw = args.pack.read_bytes()
        check(raw[:4] == b'GDPC' and struct.unpack_from('<I', raw, 4)[0] == 4, 'Godot 4.7 PCK format')
        if not failures:
            base, directory = struct.unpack_from('<QQ', raw, 24)
            number = struct.unpack_from('<I', raw, directory)[0]
            cursor = directory + 4
            entries = {}
            for _ in range(number):
                size = struct.unpack_from('<I', raw, cursor)[0]
                cursor += 4
                name = raw[cursor:cursor + size].rstrip(b'\0').decode()
                cursor += size
                offset, length = struct.unpack_from('<QQ', raw, cursor)
                cursor += 36
                entries[name.removeprefix('res://')] = raw[base + offset:base + offset + length]
            packed_clips = [name for name in entries if name.startswith('assets/hero_video/') and name.endswith('.ogv')]
            check(len(packed_clips) == 70, 'exported PCK contains all 70 native videos')
            check(all(entries[name] == (ROOT / name).read_bytes() for name in packed_clips), 'exported videos byte-identical to approved source')
            check(entries.get('assets/hero_video/manifest.json') == (ROOT / 'assets/hero_video/manifest.json').read_bytes(), 'exported manifest matches source')
            check(not any(name.startswith(('tests/', 'tools/', 'assets/hero_video_src/')) for name in entries), 'test/tools/raw sources excluded from app')
            print(f'INFO native content PCK {len(raw) / 1024**2:.1f} MiB; not signed application')
    if args.signing:
        check(platform.system() == 'Darwin', 'macOS host required for iOS export')
        check(shutil.which('xcodebuild') is not None, 'Xcode build tool available')
        team = value(options, 'application/app_store_team_id')
        bundle = value(options, 'application/bundle_identifier')
        check(bool(re.fullmatch(r'[A-Z0-9]{10}', team)), 'Apple Team ID configured')
        check(bool(re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle)), 'registered bundle identifier configured (registration must be verified separately)')
        icon = value(options, 'icons/app_store_1024x1024')
        check(icon.startswith('res://') and (ROOT / icon[6:]).is_file(), 'App Store icon configured (dimensions/alpha require visual audit)')
    print('INFO Ads, StoreKit, consent, signing, device QA and submission remain separate launch gates.')
    print('NATIVE PREFLIGHT ' + ('BLOCKED' if failures else 'PASS (source preparation only)'))
    return int(bool(failures))

if __name__ == '__main__':
    raise SystemExit(main())

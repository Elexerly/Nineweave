#!/usr/bin/env python3
"""Godot 4.7 PCK v4 directory + payload audit, no tools/downloads required."""
import hashlib
import json
from pathlib import Path
import struct
import sys


def check(root, out):
    pck = (out / 'index.pck').read_bytes()
    assert pck[:4] == b'GDPC', 'not a Godot PCK'
    assert struct.unpack_from('<I', pck, 4)[0] == 4, 'expected Godot 4.7 PCK v4'
    flags = struct.unpack_from('<I', pck, 20)[0]
    assert not flags & 1, 'encrypted PCK cannot be audited'
    base, directory = struct.unpack_from('<QQ', pck, 24)
    count, = struct.unpack_from('<I', pck, directory)
    cursor = directory + 4
    entries = {}
    for _ in range(count):
        length, = struct.unpack_from('<I', pck, cursor)
        cursor += 4
        name = pck[cursor:cursor + length].rstrip(b'\0').decode()
        cursor += length
        offset, size = struct.unpack_from('<QQ', pck, cursor)
        cursor += 36  # two u64, MD5, flags
        entries[name.removeprefix('res://')] = (base + offset, size)
    assert not any('.ogv' in name.lower() or 'hero_video_src/' in name for name in entries), 'video/source path packed'
    manifest_name = 'assets/hero_video/manifest.json'
    assert manifest_name in entries, 'manifest missing from PCK'
    offset, size = entries[manifest_name]
    catalog = json.loads(pck[offset:offset + size])
    assert catalog == json.loads((root / manifest_name).read_text()), 'packed manifest differs'
    clips = list((root / 'assets/hero_video').rglob('*.ogv'))
    for clip in clips:
        data = clip.read_bytes()
        assert data and data[:4096] not in pck, f'clip payload packed: {clip.name}'
        relative = clip.relative_to(root / 'assets/hero_video')
        sidecar = out / 'hero_video' / relative
        assert sidecar.is_file(), f'missing sidecar: {relative}'
        assert hashlib.sha256(sidecar.read_bytes()).digest() == hashlib.sha256(data).digest(), f'sidecar differs: {relative}'
    for hero_id, kinds in catalog.items():
        for kind in kinds:
            assert (out / 'hero_video' / hero_id / f'{kind}.ogv').is_file(), f'catalogued sidecar missing: {hero_id}/{kind}'
    print(f'HERO VIDEO PACK: PASS (manifest packed; {len(clips)} byte-identical sidecars; no clip paths or payloads packed)')


if __name__ == '__main__':
    try:
        check(Path(sys.argv[1]), Path(sys.argv[2]))
    except (AssertionError, OSError, ValueError, struct.error) as exc:
        print(f'HERO VIDEO PACK: FAIL ({exc})', file=sys.stderr)
        sys.exit(1)

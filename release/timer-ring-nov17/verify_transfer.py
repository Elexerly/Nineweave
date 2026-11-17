#!/usr/bin/env python3
"""Verify transfer and optionally assemble PCK only. Never edits app/DB/deployment."""
import hashlib,json,sys
from pathlib import Path
root=Path(__file__).resolve().parent
m=json.loads((root/'manifest.json').read_text())
for n,v in m['files'].items():
 p=root/n
 assert p.is_file() and p.stat().st_size==v['bytes'],f'Wrong size/missing: {n}'
 assert hashlib.sha256(p.read_bytes()).hexdigest()==v['sha256'],f'Wrong SHA256: {n}'
pack=(root/'index.pck.part-a').read_bytes()+(root/'index.pck.part-b').read_bytes()
assert len(pack)==m['assembled_pack']['bytes']
assert hashlib.sha256(pack).hexdigest()==m['assembled_pack']['sha256']
if len(sys.argv)>1:
 out=Path(sys.argv[1]).resolve()
 if out.exists():
  assert out.read_bytes()==pack, 'Refusing to overwrite different existing file'
 else:
  out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(pack)
 print('Assembled:',out)
print('TRANSFER VERIFIED:',m['assembled_pack'])

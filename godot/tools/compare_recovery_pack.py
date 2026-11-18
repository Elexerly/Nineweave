#!/usr/bin/env python3
"""Read-only comparison of unencrypted Godot 4.7 PCK v4 payloads."""
import hashlib,json,struct,sys
from pathlib import Path

def entries(path):
    b=Path(path).read_bytes()
    assert b[:4]==b'GDPC' and struct.unpack_from('<I',b,4)[0]==4
    assert not struct.unpack_from('<I',b,20)[0]&1
    base,directory=struct.unpack_from('<QQ',b,24)
    count=struct.unpack_from('<I',b,directory)[0]; cursor=directory+4; result={}
    for _ in range(count):
        length=struct.unpack_from('<I',b,cursor)[0]; cursor+=4
        name=b[cursor:cursor+length].rstrip(b'\0').decode().removeprefix('res://'); cursor+=length
        offset,size=struct.unpack_from('<QQ',b,cursor); cursor+=36
        result[name]=b[base+offset:base+offset+size]
    return result

if __name__ == "__main__":
    live,recovered=map(entries,sys.argv[1:3]); common=live.keys()&recovered.keys()
    changed=sorted(p for p in common if live[p]!=recovered[p])
    report={'live_pack_sha256':hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),
     'live_entries':len(live),'recovered_entries':len(recovered),
     'identical_entries':len(common)-len(changed),
     'compiled_scripts':sum(p.endswith('.gdc') for p in live),
     'changed':changed,'missing':sorted(live.keys()-recovered.keys()),'extra':sorted(recovered.keys()-live.keys())}
    report['all_compiled_scripts_identical']=all(p in recovered and live[p]==recovered[p] for p in live if p.endswith('.gdc'))
    print(json.dumps(report,indent=2))

#!/usr/bin/env python3
"""Convert approved roster PNGs (1024 px, transparent) into game webp art.
usage: import_hero_art.py SRC_OUT_DIR SRC_PREFIX DEST_DIR [--heads-only]
Bodies (splash/versus/victory): cropped to alpha, max 768 px tall. Heads: 256x256, uniform framing."""
import sys, os
from PIL import Image
src, pre, dst = sys.argv[1:4]; heads_only = '--heads-only' in sys.argv
os.makedirs(dst, exist_ok=True)
if not heads_only:
    for n in ['splash', 'versus', 'victory']:
        im = Image.open(f'{src}/{pre}_{n}.png').convert('RGBA')
        bb = im.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox(); im = im.crop(bb)
        if im.height > 768: im = im.resize((round(im.width * 768 / im.height), 768), Image.LANCZOS)
        im.save(f'{dst}/{n}.webp', 'WEBP', quality=86, method=6)
for n in ['neutral', 'smug', 'panic', 'doubletake', 'eyeroll', 'cheer', 'pout']:
    im = Image.open(f'{src}/{pre}_head_{n}.png').convert('RGBA').resize((256, 256), Image.LANCZOS)
    im.save(f'{dst}/head_{n}.webp', 'WEBP', quality=88, method=6)
print('imported', dst)

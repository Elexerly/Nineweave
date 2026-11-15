#!/usr/bin/env python3
"""Reproducible decorative crops only. Never crops board, UI, text or devices.
Source supplied with the project by the requester; no network assets used.
"""
from pathlib import Path
from PIL import Image, ImageFilter
import math
ROOT = Path(__file__).resolve().parents[1]
im = Image.open(ROOT/'reference/nineweave_reference.jpg').convert('RGBA')
out = ROOT/'assets/art'
out.mkdir(exist_ok=True)
def crop(name, box, fade=(0.12,0.12,0.0,0.2)):
    pic=im.crop(box)
    w,h=pic.size
    alpha=Image.new('L',(w,h)); px=alpha.load()
    for y in range(h):
        for x in range(w):
            factors=[1.0]
            if fade[0]: factors.append(x/(w*fade[0]))
            if fade[1]: factors.append((w-1-x)/(w*fade[1]))
            if fade[2]: factors.append(y/(h*fade[2]))
            if fade[3]: factors.append((h-1-y)/(h*fade[3]))
            px[x,y]=int(255*max(0,min(factors)))
    pic.putalpha(alpha)
    pic.save(out/(name+'.png'))
crop('crystal_knight',(571,0,800,390),(.16,.24,0,.2))
crop('gold_goddess',(1254,0,1500,396),(.2,0,0,.24))
crop('distant_castle',(819,297,1224,405),(.12,.12,.16,.22))
crop('crystal_cluster',(1415,639,1500,828),(.12,0,.1,.12))
# A soft sky plate, no legible UI content; clouds are layered procedurally.
sky=im.crop((815,298,1210,342)).resize((1200,800)).filter(ImageFilter.GaussianBlur(28))
sky.save(out/'sky_plate.png')
print('ART CROPS: decorative layers regenerated')
# Circular portrait from the upper-right statue face; only decorative art.
def portrait(name,box):
    pic=im.crop(box).resize((160,160),Image.Resampling.LANCZOS)
    mask=Image.new('L',(160,160)); px=mask.load()
    for y in range(160):
        for x in range(160):
            dist=math.hypot(x-79.5,y-79.5)
            px[x,y]=int(255*max(0,min(1,(79-dist)/2)))
    pic.putalpha(mask); pic.save(out/(name+'.png'))
portrait('goddess_portrait',(1264,23,1420,179))
portrait('knight_portrait',(659,14,799,154))

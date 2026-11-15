#!/usr/bin/env python3
"""Reproducible decorative crops only. Never crops board, UI, text or devices.

Round 2: every crop keeps its native pixel size (no upscaling here; the engine
caps on-screen scale at ~1.5x on a 390x844 phone) and gets a soft feathered
alpha mask (smoothstep ramps per edge, optional elliptical vignette) so the
art blends into the live backdrop with no hard rectangular edges.
Source supplied with the project by the requester; no network assets used.
"""
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
im = Image.open(ROOT/'reference/nineweave_reference.jpg').convert('RGBA')
out = ROOT/'assets/art'
out.mkdir(exist_ok=True)


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t*t*(3.0-2.0*t)


def feather_mask(w, h, fade, vignette=0.0):
    """fade = (left, right, top, bottom) as fractions of width/height; 0 keeps a hard edge
    (used only where the crop sits against a screen edge)."""
    x = (np.arange(w)+0.5)/w
    y = (np.arange(h)+0.5)/h
    X, Y = np.meshgrid(x, y)
    m = np.ones((h, w))
    left, right, top, bottom = fade
    if left: m *= smooth(X/left)
    if right: m *= smooth((1.0-X)/right)
    if top: m *= smooth(Y/top)
    if bottom: m *= smooth((1.0-Y)/bottom)
    if vignette:
        d = np.sqrt(((X-0.5)/0.5)**2+((Y-0.5)/0.5)**2)
        m *= smooth((1.25-d)/vignette)
    return m


def crop(name, box, fade, vignette=0.0, cuts=()):
    """cuts: reference-space rectangles (e.g. logo lettering) faded to zero with a soft edge."""
    pic = im.crop(box)
    w, h = pic.size
    mask = feather_mask(w, h, fade, vignette)
    if cuts:
        hole = Image.new('L', (w, h), 255)
        for c in cuts:
            hole.paste(0, (c[0]-box[0], c[1]-box[1], c[2]-box[0], c[3]-box[1]))
        hole = hole.filter(ImageFilter.GaussianBlur(14))
        mask *= np.asarray(hole)/255.0
    alpha = np.asarray(pic)[:, :, 3]/255.0*mask
    pic.putalpha(Image.fromarray((alpha*255).astype(np.uint8)))
    pic.save(out/(name+'.png'))
    return pic.size


sizes = {}
# Statues: the phone bezel ends at x~575, the logo "N" starts at x~798,
# the logo "VE" ends at x~1253 and both device frames begin at y~404.
# The knight's face reaches x~830 above the lettering, so a soft cut-out hides the "N".
sizes['crystal_knight'] = crop('crystal_knight', (580, 0, 846, 398), (.20, .22, 0, .30), .35, [(782, 140, 900, 420)])
sizes['gold_goddess'] = crop('gold_goddess', (1260, 0, 1500, 398), (.30, 0, 0, .30), .35)
# Floating castle between the ribbon plate (ends y~292) and the tablet (y~404).
sizes['distant_castle'] = crop('distant_castle', (868, 298, 1198, 402), (.20, .20, .30, .28))
# Glowing crystal clusters, bottom-right (right of the tablet) and bottom-left (left of the phone).
sizes['crystal_cluster'] = crop('crystal_cluster', (1396, 636, 1500, 832), (.22, 0, .18, .16))
sizes['crystal_cluster_left'] = crop('crystal_cluster_left', (0, 622, 84, 1000), (0, .26, .14, .12))
# Ancient arches to the right of the tablet; reused mirrored on the left in-game.
sizes['ruins'] = crop('ruins', (1380, 386, 1500, 640), (.26, .12, .18, .30))
# A soft sky plate, no legible UI content; clouds are layered procedurally.
sky = im.crop((815, 298, 1210, 342)).resize((600, 400)).filter(ImageFilter.GaussianBlur(14))
sky.save(out/'sky_plate.png')
sizes['sky_plate'] = sky.size


# Circular portraits from the statue faces; only decorative art. Downscaled, never enlarged.
def portrait(name, box, size=128):
    pic = im.crop(box).resize((size, size), Image.Resampling.LANCZOS)
    c = (size-1)/2.0
    yy, xx = np.mgrid[0:size, 0:size]
    dist = np.sqrt((xx-c)**2+(yy-c)**2)
    alpha = np.clip((c-dist)/1.5, 0, 1)
    pic.putalpha(Image.fromarray((alpha*255).astype(np.uint8)))
    pic.save(out/(name+'.png'))
    sizes[name] = pic.size


portrait('goddess_portrait', (1270, 30, 1410, 170))
portrait('knight_portrait', (712, 22, 842, 152))
for k, v in sizes.items():
    print('  %-22s %dx%d' % (k, v[0], v[1]))
print('ART CROPS: decorative layers regenerated')

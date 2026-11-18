#!/usr/bin/env python3
"""Convert only JB Circuit's approved sources. Never rewrites other hero media.

python3 convert_jb_circuit_media.py --ffmpeg /path/to/ffmpeg --inputs /path/to/jb-hero-inputs
The separate Vorbis files are retained as editable audio sources. Their packets
are copied into the OGV sidecars; HeroAudio extracts them for AudioStreamPlayer.
The overlay owns the intro's final .30s fade after the existing prelude.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--ffmpeg", required=True)
parser.add_argument("--inputs", type=Path, required=True)
args = parser.parse_args()
godot = Path(__file__).resolve().parents[1]
audio = godot.parent / "source-assets/jb-circuit/audio"
video = godot / "assets/hero_video/jb_circuit"
audio.mkdir(parents=True, exist_ok=True)
video.mkdir(parents=True, exist_ok=True)
for kind, name in [("intro", "Intro - JBTech.mp4"), ("victory", "JBCheckmate - Finishing.mp4")]:
    source = args.inputs / name
    limit = ["-t", "6"] if kind == "intro" else []
    subprocess.run([args.ffmpeg, "-v", "error", "-y", "-i", str(source),
                    "-map", "0:a:0", *limit, "-map_metadata", "-1",
                    "-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", "-ac", "2",
                    str(audio / f"{kind}.ogg")], check=True)
    subprocess.run([args.ffmpeg, "-v", "error", "-y", "-i", str(source),
                    "-i", str(audio / f"{kind}.ogg"), "-map", "0:v:0", "-map", "1:a:0", *limit,
                    "-map_metadata", "-1", "-vf", "scale=540:-2", "-r", "24",
                    "-c:v", "libtheora", "-q:v", "6", "-c:a", "copy",
                    str(video / f"{kind}.ogv")], check=True)
    print(kind, "converted with independent, unamplified Vorbis audio")

"""Copy approved Lexerly artwork into an existing Godot-exported iOS AppIcon catalog."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src" / "brand" / "Lexerly-Celestial-Icon.png"
SHA256 = "c4b643e74c9c72c0dbbe2d5b9c729d49ae7e9f687b168c4e04590ea1abc0751a"


def stage(catalog: Path) -> None:
    if catalog.name != "AppIcon.appiconset":
        raise ValueError("Provide the exported AppIcon.appiconset explicitly")
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SHA256:
        raise ValueError("The app icon is not the exact approved source PNG")
    data = json.loads((catalog / "Contents.json").read_text())
    outputs = {}
    for image in data["images"]:
        name = image.get("filename")
        if not name or not re.fullmatch(r"Icon-[0-9]+(?:-[0-9]+)?\.png", name):
            raise ValueError("Unexpected AppIcon filename")
        width, height = map(Decimal, image["size"].split("x"))
        scale = int(image.get("scale", "1x")[:-1])
        count = width * scale
        if width != height or count != int(count) or not 0 < count <= 1024:
            raise ValueError("Unexpected AppIcon size")
        outputs[name] = int(count)
    if 1024 not in outputs.values():
        raise ValueError("No 1024px AppIcon slot")
    for name, pixels in outputs.items():
        output = catalog / name
        if pixels == 1024:
            shutil.copyfile(SOURCE, output)
        else:
            subprocess.run(
                ["/usr/bin/sips", "-z", str(pixels), str(pixels), str(SOURCE), "--out", str(output)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
    print(f"Staged {len(outputs)} AppIcon entries, preserving the original 1024px PNG.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", type=Path)
    stage(parser.parse_args().catalog)

#!/usr/bin/env python3
"""Generate Notebar's MSIX tile assets and Windows .ico from the shared icon.

Run from the repo root:  python3 windows/scripts/make-msix-assets.py
Requires Pillow: pip3 install Pillow
"""
import importlib.util
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "windows", "Notebar.App", "Assets")

spec = importlib.util.spec_from_file_location(
    "make_icon", os.path.join(ROOT, "scripts", "make-icon.py"))
make_icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_icon)

master = make_icon.render()
os.makedirs(OUT, exist_ok=True)

for name, size in [("Square44x44Logo.png", 44),
                   ("Square150x150Logo.png", 150),
                   ("StoreLogo.png", 50)]:
    master.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))

# Wide tile: the square mark centred on a transparent 310x150 field.
wide = Image.new("RGBA", (310, 150), (0, 0, 0, 0))
sq = master.resize((150, 150), Image.LANCZOS)
wide.paste(sq, (80, 0), sq)
wide.save(os.path.join(OUT, "Wide310x150Logo.png"))

# .ico for the portable build's window and taskbar icon.
master.save(os.path.join(OUT, "Notebar.ico"),
            sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

print("wrote", OUT)

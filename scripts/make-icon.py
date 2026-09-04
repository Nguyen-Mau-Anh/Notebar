#!/usr/bin/env python3
"""Generate Notebar's app icon.

Kept in the repo so the icon is reproducible rather than an opaque binary
nobody can regenerate. Requires Pillow: pip3 install Pillow

    python3 scripts/make-icon.py     ->  Notebar/Resources/AppIcon.icns

The mark is the app's own geometry: a panel flush to the right edge, left
corners rounded and right corners square against the boundary, exactly as the
real panel sits against the screen. Field colour is the accent blue the UI uses.
"""
from PIL import Image, ImageDraw
import math, os, shutil, subprocess, sys

MASTER = 1024
SS = 2                      # supersample, then downsample for clean edges
W = MASTER * SS
OUT = os.path.join("Notebar", "Resources", "AppIcon.icns")

BLUE_TOP, BLUE_BOTTOM = (10, 132, 255), (0, 86, 208)
PANEL = (252, 252, 254)
LINE = (168, 173, 184)


def squircle(size, n=5.0):
    """macOS uses a superellipse, not a rounded rectangle. n=5 matches closely."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    c = r = size / 2
    pts = []
    for i in range(1440):
        t = 2 * math.pi * i / 1440
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + r * math.copysign(abs(ct) ** (2 / n), ct),
                    c + r * math.copysign(abs(st) ** (2 / n), st)))
    d.polygon(pts, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        f = y / max(1, size - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3)))
    return g.resize((size, size), Image.BICUBIC)


def rounded(d, box, radius, fill, corners=(1, 1, 1, 1)):
    """Rounded rect with per-corner control: (top-left, top-right, bottom-right, bottom-left)."""
    x0, y0, x1, y1 = box
    tl, tr, br, bl = [radius if c else 0 for c in corners]
    d.rectangle([x0 + tl, y0, x1 - tr, y1], fill=fill)
    d.rectangle([x0, y0 + tl, x1, y1 - bl], fill=fill)
    if tl: d.pieslice([x0, y0, x0 + 2*tl, y0 + 2*tl], 180, 270, fill=fill)
    if tr: d.pieslice([x1 - 2*tr, y0, x1, y0 + 2*tr], 270, 360, fill=fill)
    if br: d.pieslice([x1 - 2*br, y1 - 2*br, x1, y1], 0, 90, fill=fill)
    if bl: d.pieslice([x0, y1 - 2*bl, x0 + 2*bl, y1], 90, 180, fill=fill)


def render():
    mask = squircle(W)
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    img.paste(vertical_gradient(W, BLUE_TOP, BLUE_BOTTOM).convert("RGBA"), (0, 0), mask)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    panel_w = int(W * 0.46)
    x0 = W - panel_w
    y0, y1 = int(W * 0.175), int(W * 0.825)
    rounded(d, (x0, y0, W, y1), int(W * 0.075), PANEL, corners=(1, 0, 0, 1))

    line_x = x0 + int(panel_w * 0.20)
    line_w = panel_w - int(panel_w * 0.36)
    for i, frac in enumerate([1.0, 1.0, 0.58]):
        ly = y0 + int((y1 - y0) * (0.28 + i * 0.20))
        h = int(W * 0.034)
        rounded(d, (line_x, ly, line_x + int(line_w * frac), ly + h), h // 2, LINE)

    # Clip the panel to the squircle so it meets the edge exactly.
    layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (W, W), 0), mask))
    return Image.alpha_composite(img, layer).resize((MASTER, MASTER), Image.LANCZOS)


def main():
    master = render()
    iconset = "AppIcon.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for size in (16, 32, 128, 256, 512):
        master.resize((size, size), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}.png")
        master.resize((size * 2, size * 2), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}@2x.png")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
    shutil.rmtree(iconset)
    print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB)")


if __name__ == "__main__":
    sys.exit(main())

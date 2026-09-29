#!/usr/bin/env python3
"""Turn AI-generated character images (white background, art facing UP) into game sprites.

Usage: python3 tools/make_comic_sprites.py ~/Downloads/yard-wars-art

For each <name>.png in NAMES: remove the white background (flood fill from the image
border, so white inside the outline stays), shrink the mask a little to drop the JPEG
fringe, trim, scale to a fixed width and save to assets/images/comic/<name>.png.
Prints the body origin and muzzle (in output pixels) to put into src/rowdies.lua.
"""
import collections
import os
import sys

from PIL import Image, ImageFilter

NAMES = ["gunner", "shotgunner", "sniper", "bot"]
WIDTH = 88        # output width in px (drawn at Assets.comicScale = 0.5 -> 44 world px)
WHITE = 225       # background = all channels at least this bright
PAD = 2           # transparent border around the trimmed sprite
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "comic")


def background_mask(im):
    """255 = character, 0 = background reachable from the border."""
    w, h = im.size
    px = im.load()
    mask = Image.new("L", (w, h), 255)
    m = mask.load()
    border = [(x, y) for x in range(w) for y in (0, h - 1)] + \
             [(x, y) for y in range(h) for x in (0, w - 1)]
    seen = set(border)
    queue = collections.deque(border)
    while queue:
        x, y = queue.popleft()
        if min(px[x, y]) < WHITE:
            continue
        m[x, y] = 0
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen:
                seen.add(n)
                queue.append(n)
    # Erode by ~2px (outlines are ~12px thick) and soften the edge
    return mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1))


def process(src_dir, name):
    im = Image.open(os.path.join(src_dir, name + ".png")).convert("RGB")
    rgba = im.convert("RGBA")
    rgba.putalpha(background_mask(im))
    bbox = rgba.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    rgba = rgba.crop(bbox)
    k = WIDTH / rgba.width
    rgba = rgba.resize((WIDTH, round(rgba.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (rgba.width + 2 * PAD, rgba.height + 2 * PAD))
    out.alpha_composite(rgba, (PAD, PAD))
    out.save(os.path.join(OUT_DIR, name + ".png"))

    # Body origin: centre of a circle as wide as the sprite resting on its bottom edge
    # (the head/shoulders); muzzle: topmost opaque pixel (the weapon points up).
    w, h = out.size
    ox, oy = w / 2, h - PAD - WIDTH / 2
    alpha = out.getchannel("A").load()
    top = next(y for y in range(h) if any(alpha[x, y] > 128 for x in range(w)))
    xs = [x for x in range(w) if alpha[x, top] > 128]
    tip_x = (xs[0] + xs[-1]) / 2
    print(f"{name:10s} size {w}x{h}  origin {{ {ox:g}, {oy:g} }}  "
          f"muzzle {{ {oy - top:g}, {tip_x - ox:g} }}  (source bbox {bbox})")


def main():
    src_dir = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/yard-wars-art")
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in NAMES:
        process(src_dir, name)


if __name__ == "__main__":
    main()

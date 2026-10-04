#!/usr/bin/env python3
"""Turn AI-generated character images (white background, art facing UP) into game sprites.

Usage: python3 tools/make_comic_sprites.py ~/Downloads/yard-wars-art [name ...]
       python3 tools/make_comic_sprites.py --side ~/Downloads/yard-wars-art-new/side [name ...]

For each <name>.png in NAMES (or only the names given): remove the white background
(flood fill from the image border, plus enclosed white areas of at least HOLE_MIN px, e.g.
between arms and weapon; smaller white spots inside the outline stay), shrink the mask a little to drop the JPEG
fringe, trim, scale to a fixed width and save to assets/images/comic/<name>.png.
Prints the body origin and muzzle (in output pixels) to put into src/rowdies.lua.

--scale K: scale every image by K instead of to WIDTH (keeps the sizes the images were
drawn at: a slim sniper isn't blown up to the width of the others; 0.27 for
~/Downloads/yard-wars-art-new/top makes the gunner 88px wide).

--side: side views (standing, facing right) for the lobby: same cut-out, scaled to
SIDE_HEIGHT px tall (enclosed white stays: eyes), reduced to 256 colours (1/6 of the size, looks the same for comic
art; keeps the game download small), saved to assets/images/side/<name>.png.
"""
import collections
import os
import sys

from PIL import Image, ImageFilter

NAMES = ["gunner", "shotgunner", "sniper", "bot", "robot"]
WIDTH = 88        # output width in px (drawn at Assets.comicScale = 0.5 -> 44 world px)
WHITE = 225       # background = all channels at least this bright
PAD = 2           # transparent border around the trimmed sprite
HOLE_MIN = 200    # enclosed white areas this big (source px) are background too
SIDE_NAMES = ["gunner", "shotgunner", "sniper", "robot"]
SIDE_HEIGHT = 400  # lobby: drawn up to ~300 HUD px tall, x2 for high-DPI screens
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "comic")
SIDE_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "side")


def white_area(px, w, h, start, seen):
    """Pixels of the white area around start (4-connected), marking them in seen."""
    area, queue = [], collections.deque([start])
    seen.add(start)
    while queue:
        x, y = queue.popleft()
        area.append((x, y))
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and min(px[n]) >= WHITE:
                seen.add(n)
                queue.append(n)
    return area


def background_mask(im, holes=True):
    """255 = character, 0 = background: white reachable from the border, and enclosed
    white areas of at least HOLE_MIN px (gaps between arms and weapon)."""
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
    for y in range(h if holes else 0):
        for x in range(w):
            if (x, y) not in seen and min(px[x, y]) >= WHITE:
                area = white_area(px, w, h, (x, y), seen)
                if len(area) >= HOLE_MIN:
                    for p in area:
                        m[p] = 0
    # Erode by ~2px (outlines are ~12px thick) and soften the edge
    return mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1))


def cut_out(src_dir, name, holes=True):
    im = Image.open(os.path.join(src_dir, name + ".png")).convert("RGB")
    rgba = im.convert("RGBA")
    rgba.putalpha(background_mask(im, holes))
    bbox = rgba.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    return rgba.crop(bbox), bbox


def process_side(src_dir, name):
    rgba, bbox = cut_out(src_dir, name, holes=False) # eyes are enclosed white areas
    k = SIDE_HEIGHT / rgba.height
    rgba = rgba.resize((round(rgba.width * k), SIDE_HEIGHT), Image.LANCZOS)
    out = Image.new("RGBA", (rgba.width + 2 * PAD, rgba.height + 2 * PAD))
    out.alpha_composite(rgba, (PAD, PAD))
    out = out.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    out.save(os.path.join(SIDE_DIR, name + ".png"), optimize=True)
    print(f"{name:10s} side view {out.width}x{out.height}  (source bbox {bbox})")


def process(src_dir, name, scale=None):
    rgba, bbox = cut_out(src_dir, name)
    k = scale or WIDTH / rgba.width
    rgba = rgba.resize((round(rgba.width * k), round(rgba.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (rgba.width + 2 * PAD, rgba.height + 2 * PAD))
    out.alpha_composite(rgba, (PAD, PAD))
    out.save(os.path.join(OUT_DIR, name + ".png"))

    # Body origin: centre of a circle as wide as the sprite resting on its bottom edge
    # (the head/shoulders); muzzle: topmost opaque pixel (the weapon points up).
    w, h = out.size
    ox, oy = w / 2, h - PAD - rgba.width / 2
    alpha = out.getchannel("A").load()
    top = next(y for y in range(h) if any(alpha[x, y] > 128 for x in range(w)))
    xs = [x for x in range(w) if alpha[x, top] > 128]
    tip_x = (xs[0] + xs[-1]) / 2
    print(f"{name:10s} size {w}x{h}  origin {{ {ox:g}, {oy:g} }}  "
          f"muzzle {{ {oy - top:g}, {tip_x - ox:g} }}  (source bbox {bbox})")


def main():
    args, side, scale = sys.argv[1:], False, None
    while args and args[0].startswith("--"):
        if args[0] == "--side":
            side, args = True, args[1:]
        elif args[0] == "--scale":
            scale, args = float(args[1]), args[2:]
        else:
            sys.exit("unknown option " + args[0])
    src_dir = os.path.expanduser(args[0] if args else "~/Downloads/yard-wars-art")
    if side:
        os.makedirs(SIDE_DIR, exist_ok=True)
        for name in args[1:] or SIDE_NAMES:
            process_side(src_dir, name)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in args[1:] or NAMES:
        process(src_dir, name, scale)


if __name__ == "__main__":
    main()

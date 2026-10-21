# -*- coding: utf-8 -*-
"""
App icon generator (run: py -3 scripts/make_icon.py)

Design (Ruyi Mental Math): white exercise notebook with blue spine and wavy
handwriting lines, an orange pencil laid diagonally across the bottom-right
corner, on a vertical brand-blue gradient background.

Layers (HarmonyOS layered icon):
  - background.png : gradient, opaque, full-bleed 1024
  - foreground.png : notebook + pencil, centered in the ~60% safe zone
  - flattened composite for legacy app_icon.png / startIcon.png
  - squircle-masked preview for quick visual check

All drawing is done at 4x supersample (4096) and downscaled with LANCZOS.
"""

import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_MEDIA = os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media')
ENTRY_MEDIA = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media')
SHOTS = os.path.join(ROOT, '.ui_shots')

SIZE = 1024
SS = 4
BIG = SIZE * SS  # 4096

TOP = (69, 128, 224)      # #4580E0
BOTTOM = (46, 111, 214)   # #2E6FD6
WHITE = (255, 255, 255, 255)
BLUE = (46, 111, 214, 255)      # spine / wave ink
WOOD = (232, 195, 158, 255)     # pencil wood cone
GRAPHITE = (74, 74, 74, 255)    # pencil tip
PENCIL = (245, 166, 35, 255)    # pencil body (app accent)
FERRULE = (201, 206, 214, 255)  # metal band
ERASER = (239, 154, 154, 255)   # pink eraser


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_background():
    img = Image.new('RGB', (SIZE, SIZE))
    dr = ImageDraw.Draw(img)
    for y in range(SIZE):
        dr.line([(0, y), (SIZE, y)], fill=lerp(TOP, BOTTOM, y / (SIZE - 1)))
    return img


def wave_points(x0, x1, yc, amp, wave_len, step=40):
    pts = []
    x = x0
    while x <= x1:
        pts.append((x, yc + amp * math.sin(2 * math.pi * (x - x0) / wave_len)))
        x += step
    return pts


def make_notebook_layer():
    """Flat notebook (2000x2400 in 4096-space), rotated -4 deg by caller."""
    img = Image.new('RGBA', (2000, 2400), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    # blue spine with rounded outer corners
    dr.rounded_rectangle((0, 0, 560, 2400), radius=120, fill=BLUE)
    # white paper on top (covers spine's right part, keeps right corners rounded)
    dr.rounded_rectangle((280, 0, 2000, 2400), radius=120, fill=WHITE)
    # binding rings down the spine
    for y in (300, 750, 1200, 1650, 2100):
        dr.ellipse((30, y - 110, 250, y + 110), fill=WHITE)
    # wavy handwriting lines
    dr.line(wave_points(520, 1840, 760, 110, 560), fill=BLUE, width=56, joint='curve')
    dr.line(wave_points(520, 1840, 1330, 110, 560), fill=BLUE, width=56, joint='curve')
    dr.line(wave_points(520, 1300, 1900, 110, 560), fill=BLUE, width=56, joint='curve')
    return img


def make_pencil_layer():
    """Horizontal pencil (1800x460 in 4096-space), tip at left; rotated by caller."""
    img = Image.new('RGBA', (1800, 460), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.polygon([(20, 230), (360, 20), (360, 440)], fill=WOOD)          # wood cone
    dr.polygon([(20, 230), (170, 146), (170, 314)], fill=GRAPHITE)     # graphite tip
    dr.rectangle((360, 20, 1420, 440), fill=PENCIL)                    # body
    dr.rectangle((1420, 20, 1560, 440), fill=FERRULE)                  # metal band
    dr.rounded_rectangle((1560, 20, 1780, 440), radius=110, fill=ERASER)
    return img


def composite_centered(base, layer, cx, cy, angle):
    rot = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    base.alpha_composite(rot, (cx - rot.width // 2, cy - rot.height // 2))


def make_foreground():
    img = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    composite_centered(img, make_notebook_layer(), 1880, 1900, -4)
    composite_centered(img, make_pencil_layer(), 2560, 2640, -45)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(SHOTS, exist_ok=True)
    bg = make_background()
    fg = make_foreground()

    bg.save(os.path.join(APP_MEDIA, 'background.png'))
    fg.save(os.path.join(APP_MEDIA, 'foreground.png'))

    flat = bg.convert('RGBA')
    flat.alpha_composite(fg)
    flat = flat.convert('RGB')
    flat.save(os.path.join(APP_MEDIA, 'app_icon.png'))
    flat.save(os.path.join(ENTRY_MEDIA, 'app_icon.png'))
    flat.save(os.path.join(ENTRY_MEDIA, 'startIcon.png'))

    flat.resize((512, 512), Image.LANCZOS).save(os.path.join(SHOTS, 'icon_preview.png'))

    masked = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=225, fill=255)
    masked.paste(flat, (0, 0), mask)
    masked.resize((512, 512), Image.LANCZOS).save(os.path.join(SHOTS, 'icon_preview_masked.png'))

    for name in ('background.png', 'foreground.png', 'app_icon.png'):
        p = os.path.join(APP_MEDIA, name)
        print(name, Image.open(p).size, os.path.getsize(p), 'bytes')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Generates the Finder window background for the LiteSwitcher DMG.

Renders two files next to this script:
  background.png     (660 x 400, 1x)
  background@2x.png  (1320 x 800, 2x, for Retina displays)

Requires Pillow (pip install pillow). Tweak the geometry below; keep the
values in sync with dmg/settings.py (icon_locations).
"""
from PIL import Image, ImageDraw, ImageFilter
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# --- layout (logical points, matches dmg/settings.py icon_locations) -----
W, H = 660, 400                 # window content size
ICON_CY = 160                   # vertical center of the icons
APP_CX = 170                    # center of the app icon
APPS_CX = 490                   # center of the Applications icon

# --- colors ---------------------------------------------------------------
TOP = (239, 242, 251)
BOTTOM = (202, 213, 246)
ARROW = (107, 92, 231)          # violet

S = 2                           # supersample factor for crisp 2x output

WW, HH = W * S, H * S
CX = (APP_CX + APPS_CX) // 2    # arrow center x
CY = ICON_CY


def scaled(*vals):
    return [v * S for v in vals]


# Vertical gradient base --------------------------------------------------
grad = Image.new("RGB", (1, HH))
for y in range(HH):
    t = y / (HH - 1)
    grad.putpixel((0, y), tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
base = grad.resize((WW, HH)).convert("RGBA")

# Soft decorative blobs ---------------------------------------------------
blobs = Image.new("RGBA", (WW, HH), (0, 0, 0, 0))
bd = ImageDraw.Draw(blobs)
bd.ellipse(scaled(-220, -160, 430, 490), fill=(183, 167, 232, 66))
bd.ellipse(scaled(WW - 470, HH - 400, WW + 140, HH + 60), fill=(167, 199, 241, 88))
bd.ellipse(scaled(WW - 360, -260, WW + 40, 150), fill=(255, 255, 255, 60))
blobs = blobs.filter(ImageFilter.GaussianBlur(S * 60))
img = Image.alpha_composite(base, blobs)


def draw_arrow(draw, cx, cy, fill):
    """Draws a plain right-pointing arrow: a rectangular shaft and a triangular head."""
    draw.rectangle(scaled(cx - 80, cy - 10, cx + 32, cy + 10), fill=fill)
    draw.polygon(scaled(cx + 32, cy - 20, cx + 32, cy + 20, cx + 80, cy), fill=fill)


draw_arrow(ImageDraw.Draw(img), CX, CY, ARROW + (255,))

# Save 1x and 2x -----------------------------------------------------------
img2x = img.convert("RGB")
img2x.save(os.path.join(HERE, "background@2x.png"))
img2x.resize((W, H), Image.LANCZOS).save(os.path.join(HERE, "background.png"))
print("wrote background.png and background@2x.png")

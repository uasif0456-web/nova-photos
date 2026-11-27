#!/usr/bin/env python3
"""Generate the original NOVA PHOTOS app icon with PIL.

The mark: a geometric nova burst — an eight-point star over three
aurora arcs (violet -> teal -> rose) on a deep-indigo night sky.
Everything is drawn from primitives here; no stock art, no copied
logos, no Google Photos colours.

Outputs (1024x1024 unless noted):
  assets/icons/icon.png            — full icon (background + mark)
  assets/icons/icon_foreground.png — adaptive-icon foreground (transparent)
  assets/icons/icon_background.png — adaptive-icon background (solid indigo)
  assets/icons/icon_monochrome.png — adaptive-icon monochrome (white mark)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(HERE)
OUT = os.path.join(PROJECT_ROOT, "assets", "icons")
os.makedirs(OUT, exist_ok=True)

SIZE = 1024
SS = 4  # supersample factor
W = SIZE * SS
CX = CY = W // 2

INDIGO_DEEP = (20, 16, 46, 255)
INDIGO = (36, 26, 94, 255)
VIOLET = (124, 92, 255, 255)
VIOLET_LIGHT = (168, 148, 255, 255)
TEAL = (45, 212, 191, 255)
ROSE = (244, 114, 182, 255)
WHITE = (255, 255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def star_points(cx, cy, r_outer, r_inner, points=8, rotation=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        r = r_outer if i % 2 == 0 else r_inner
        ang = rotation + i * math.pi / points
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def draw_mark(img, scale=1.0):
    """Draw the nova burst + aurora arcs centred on the canvas."""
    draw = ImageDraw.Draw(img)
    # --- Aurora arcs: three concentric arcs, violet -> teal -> rose.
    # Each arc is a thick ring segment sweeping the lower sky.
    arc_colours = [VIOLET, TEAL, ROSE]
    for i, colour in enumerate(arc_colours):
        r = int(W * (0.30 + i * 0.075) * scale)
        width = int(W * 0.022 * scale)
        bbox = [CX - r, CY - r, CX + r, CY + r]
        # Sweep from 15 deg to 165 deg (an arch over the star).
        draw.arc(bbox, start=195, end=345, fill=colour, width=width)

    # --- Nova burst: glow + crisp eight-point star.
    glow_r = int(W * 0.20 * scale)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        [CX - glow_r, CY - glow_r, CX + glow_r, CY + glow_r],
        fill=(124, 92, 255, 110),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(W * 0.03)))
    img.alpha_composite(glow)
    draw = ImageDraw.Draw(img)

    star = star_points(CX, CY, int(W * 0.155 * scale), int(W * 0.052 * scale))
    draw.polygon(star, fill=WHITE)
    inner = star_points(CX, CY, int(W * 0.085 * scale), int(W * 0.030 * scale))
    draw.polygon(inner, fill=VIOLET_LIGHT)

    # Four sparkle dots on the arcs.
    for ang_deg, r_frac, rr in [(215, 0.375, 0.012), (325, 0.375, 0.012),
                                (250, 0.45, 0.010), (290, 0.45, 0.010)]:
        ang = math.radians(ang_deg)
        r = W * r_frac * scale
        x, y = CX + r * math.cos(ang), CY + r * math.sin(ang)
        d = W * rr * scale
        draw.ellipse([x - d, y - d, x + d, y + d], fill=WHITE)


def radial_background():
    """Deep-indigo radial gradient (bright centre -> dark corners)."""
    img = Image.new("RGBA", (W, W), INDIGO_DEEP)
    # Cheap radial gradient: concentric ellipses, centre bright.
    steps = 64
    max_r = int(W * 0.75)
    for i in range(steps, 0, -1):
        t = i / steps
        colour = lerp(INDIGO, INDIGO_DEEP, t)
        r = int(max_r * t)
        d = ImageDraw.Draw(img)
        d.ellipse([CX - r, CY - r, CX + r, CY + r], fill=colour)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)
    return mask


def save(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name), "PNG")
    print("wrote", name)


# --- Full icon: gradient sky + mark, rounded-square mask (launcher style).
full = radial_background()
draw_mark(full)
full.putalpha(rounded_mask(W, int(W * 0.22)))
save(full, "icon.png")

# --- Adaptive foreground: transparent background, mark only.
fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw_mark(fg, scale=0.85)
save(fg, "icon_foreground.png")

# --- Adaptive background: solid deep indigo.
bg = Image.new("RGBA", (W, W), INDIGO_DEEP)
save(bg, "icon_background.png")

# --- Monochrome: white mark on transparent (for themed icons).
mono = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw = ImageDraw.Draw(mono)
# Same geometry, all-white.
orig_violet, orig_teal, orig_rose = VIOLET, TEAL, ROSE
# Temporarily draw with white arcs by re-running a white variant.
for i in range(3):
    r = int(W * (0.30 + i * 0.075) * 0.85)
    width = int(W * 0.022 * 0.85)
    bbox = [CX - r, CY - r, CX + r, CY + r]
    draw.arc(bbox, start=195, end=345, fill=WHITE, width=width)
star = star_points(CX, CY, int(W * 0.155 * 0.85), int(W * 0.052 * 0.85))
draw.polygon(star, fill=WHITE)
save(mono, "icon_monochrome.png")

print("done")

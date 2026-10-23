#!/usr/bin/env python3
"""Rasterise the Township of Tomorrow launcher icon PNGs (5 densities x 2).

DESIGN SOURCE = tool/icons/app_icon.svg (+ app_icon_foreground.svg for the
adaptive foreground). ImageMagick in this container only has its internal
MSVG renderer, which cannot do gradients or stroked arcs, so this script
mirrors the SVG's exact geometry with Pillow instead: every constant below
is the same number that appears in the SVG.

Layers (see app_icon.svg):
  1. tile     — squircle, soft top-light gradient #388E3C->#2E7D32->#1B5E20
  2. loop     — three chasing arrows (white), top gap centred at 90 deg
  3. leaf     — light-green sprout out of the loop's top opening

Output: <outdir>/mipmap-<dpi>/ic_launcher.png        (legacy, full-bleed tile)
        <outdir>/mipmap-<dpi>/ic_launcher_foreground.png (108dp grid, alpha)

Usage: make_icon_pngs.py <outdir>        (default: ./staged)
"""
import math
import os
import sys

from PIL import Image, ImageDraw

# ---------------------------------------------------------------- geometry --
N = 108.0                      # adaptive-icon canvas, dp
C = 54.0                       # centre
R = 24.0                       # loop band mid radius
SW = 8.0                       # loop band stroke width
HEAD_HALF = 8.0                # arrowhead base half-width (r 16..32)
HEAD_BASE_DEG = 90.0           # arrowhead base sits at end of the 0->90 arc
HEAD_TIP_DEG = 106.0           # arrowhead tip, 16 deg ahead along the loop
GROUP_ROT = 23.0               # SVG rotate(23 54 54): top gap -> 90 deg
COPY_ROTS = (0.0, 120.0, 240.0)  # SVG rotate(120/240 54 54)
LEAF_BASE = (54.0, 34.0)       # quadratic bezier, matches SVG path
LEAF_CTRL_L = (48.0, 27.0)
LEAF_TIP = (57.0, 20.0)
LEAF_CTRL_R = (62.5, 28.0)
TILE_RX = 24.0                 # squircle corner radius on the 108 grid
GRAD = [                       # soft top-light, stops from the SVG
    (0.00, (0x38, 0x8E, 0x3C)),
    (0.45, (0x2E, 0x7D, 0x32)),
    (1.00, (0x1B, 0x5E, 0x20)),
]
WHITE = (255, 255, 255, 255)
LEAF_COL = (0xC8, 0xE6, 0xC9, 255)

LEGACY = {48: "mdpi", 72: "hdpi", 96: "xhdpi", 144: "xxhdpi", 192: "xxxhdpi"}
FOREGROUND = {108: "mdpi", 162: "hdpi", 216: "xhdpi",
              324: "xxhdpi", 432: "xxxhdpi"}
SS = 4                          # supersample factor, LANCZOS down afterwards


def polar(r, deg):
    """Point on the 108 grid; deg is visual counter-clockwise (y flipped)."""
    a = math.radians(deg)
    return (C + r * math.cos(a), C - r * math.sin(a))


def svg_rot(p, deg):
    """SVG rotate(deg) about the origin (y-down => positive = clockwise)."""
    a = math.radians(deg)
    x, y = p
    return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a))


def xf(p, deg):
    """SVG rotate(deg) about (54,54)."""
    q = svg_rot((p[0] - C, p[1] - C), deg)
    return (C + q[0], C + q[1])


def quad_bezier(p0, q, p1, steps=64):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        m = 1.0 - t
        pts.append((m * m * p0[0] + 2 * m * t * q[0] + t * t * p1[0],
                    m * m * p0[1] + 2 * m * t * q[1] + t * t * p1[1]))
    return pts


def arrow_polygons():
    """One arrow in base coords (arc band + head), then rotated copies."""
    outer = [polar(R + SW / 2, HEAD_BASE_DEG * i / 96.0) for i in range(97)]
    inner = [polar(R - SW / 2, HEAD_BASE_DEG * i / 96.0) for i in range(96, -1, -1)]
    band = outer + inner
    head = [polar(R - HEAD_HALF, HEAD_BASE_DEG),
            polar(R + HEAD_HALF, HEAD_BASE_DEG),
            polar(R, HEAD_TIP_DEG)]
    out = []
    for rot in COPY_ROTS:
        out.append(([xf(xf(p, rot), GROUP_ROT) for p in band],
                    [xf(xf(p, rot), GROUP_ROT) for p in head]))
    return out


def leaf_polygon():
    return quad_bezier(LEAF_BASE, LEAF_CTRL_L, LEAF_TIP) + \
           quad_bezier(LEAF_TIP, LEAF_CTRL_R, LEAF_BASE)


def scale(pts, s):
    return [(x * s, y * s) for x, y in pts]


def grad_color(t):
    for (t0, c0), (t1, c1) in zip(GRAD, GRAD[1:]):
        if t <= t1:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return GRAD[-1][1]


def draw_glyph(img, factor):
    """Arrow loop + leaf, in 108-grid coords scaled by `factor`
    (factor = px * SS / 108, i.e. grid units -> supersampled canvas px)."""
    d = ImageDraw.Draw(img)
    for band, head in arrow_polygons():
        d.polygon(scale(band, factor), fill=WHITE)
        d.polygon(scale(head, factor), fill=WHITE)
    d.polygon(scale(leaf_polygon(), factor), fill=LEAF_COL)


def render_legacy(px):
    """Full-bleed squircle tile + glyph; transparent outside the corners."""
    w = px * SS
    tile = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    rows = Image.new("RGB", (w, w))
    dr = ImageDraw.Draw(rows)
    for y in range(w):
        dr.line([(0, y), (w, y)], fill=grad_color(y / (w - 1)))
    mask = Image.new("L", (w, w), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, w - 1, w - 1], radius=round(TILE_RX / N * w), fill=255)
    tile.paste(rows, (0, 0), mask)
    draw_glyph(tile, w / N)
    return tile.resize((px, px), Image.LANCZOS)


def render_foreground(px):
    """Glyph only on transparent — adaptive background comes from colors.xml."""
    w = px * SS
    fg = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    draw_glyph(fg, w / N)
    return fg.resize((px, px), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "staged")
    for name, table, fn in (("ic_launcher", LEGACY, render_legacy),
                            ("ic_launcher_foreground", FOREGROUND,
                             render_foreground)):
        for px, dpi in table.items():
            path = os.path.join(out, f"mipmap-{dpi}", f"{name}.png")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            fn(px).save(path, "PNG")
            print(f"wrote {path} ({px}x{px})")


if __name__ == "__main__":
    main()

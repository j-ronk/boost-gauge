#!/usr/bin/env python3
"""Writes the Boost Gauge glyph layers into AppIcon.icon/Assets.

Usage: python3 Design/icon/glyphs.py
The background gradient, glass and dark colours live in AppIcon.icon/icon.json.
"""
import math
import os

S = 1024
CX, CY, R0 = 512, 580, 196
N, A_START, SPAN, GAP = 8, 212, 244, 9
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.icon", "Assets")


def pt(r, deg):
    a = math.radians(deg)
    return CX + r * math.cos(a), CY - r * math.sin(a)


def sector(r0, r1, a0, a1):
    (ox0, oy0), (ox1, oy1) = pt(r1, a0), pt(r1, a1)
    (ix1, iy1), (ix0, iy0) = pt(r0, a1), pt(r0, a0)
    return (f"M{ox0:.1f},{oy0:.1f} A{r1},{r1} 0 0 1 {ox1:.1f},{oy1:.1f} "
            f"L{ix1:.1f},{iy1:.1f} A{r0},{r0} 0 0 0 {ix0:.1f},{iy0:.1f} Z")


def segment(i, fill):
    slot = SPAN / N
    a0 = A_START - i * slot - GAP / 2
    # The outer edge grows with each step so the bar reads as climbing boost.
    d = sector(R0, 270 + i * 13, a0, a0 - slot + GAP)
    # Apple asks for no sharp corners; they break up at small sizes.
    return f'<path d="{d}" fill="{fill}" stroke="{fill}" stroke-width="22" stroke-linejoin="round"/>'


def write(name, indices, fill):
    body = "".join(segment(i, fill) for i in indices)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" '
           f'viewBox="0 0 {S} {S}">{body}</svg>\n')
    with open(os.path.join(ASSETS, name), "w") as f:
        f.write(svg)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    write("bars.svg", range(N - 2), "#FFFFFF")
    write("warn.svg", [N - 2], "#FFD60A")
    write("redline.svg", [N - 1], "#FF453A")


if __name__ == "__main__":
    main()

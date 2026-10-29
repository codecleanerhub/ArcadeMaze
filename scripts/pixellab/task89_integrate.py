#!/usr/bin/env python3
"""TASK 89 — integra l'asset lance: 128x128 statico -> sheet 4 varianti.

spear_tips.png (statico PixelLab) viene affettato in 4 quadranti 64x64
-> spear_tips_sheet.png (256x64) + meta standard. 0 generazioni extra.
"""
from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import pl_integrate

SPR = pl_integrate.GODOT_SPRITES


def quad_frames(img: Image.Image) -> list[Image.Image]:
    assert img.size == (128, 128), f"atteso 128x128, trovato {img.size}"
    out = []
    for cy in range(2):
        for cx in range(2):
            q = img.crop((cx * 64, cy * 64, cx * 64 + 64, cy * 64 + 64))
            opaque = sum(1 for p in q.getdata() if p[3] > 0)
            if opaque < 64 * 64 * 0.02:
                continue
            out.append(q)
    return out


def main() -> None:
    src_abs = os.path.join(SPR, "hazards/spear_tips.png")
    if not os.path.isfile(src_abs):
        print("[task89] MANCA spear_tips.png — generare con pl_run.py static")
        sys.exit(1)
    img = Image.open(src_abs).convert("RGBA")
    frames = quad_frames(img)
    while len(frames) < 4 and frames:
        frames.append(frames[len(frames) % max(1, len(frames))])
    if len(frames) < 4:
        print("[task89] nessun quadrante valido")
        sys.exit(1)
    out = pl_integrate.write_anim_sheet(
        "hazards/spear_tips_sheet.png", frames, frame_px=64, feet_y=56,
        anchor=(32, 40))
    print(f"[task89] sheet 4-varianti -> {out}")


if __name__ == "__main__":
    main()

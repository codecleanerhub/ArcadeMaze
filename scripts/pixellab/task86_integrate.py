#!/usr/bin/env python3
"""TASK 86 — integra gli asset statici PixelLab come sheet 4-frame.

bossdeath_rubble.png / bossdeath_bones.png (128x128 statici generati da
pl_run.py) vengono affettati in 4 quadranti 64x64 -> sheet 256x64 +
meta standard del gioco (pattern write_anim_sheet di pl_integrate).
0 generazioni extra: post-processing locale gratuito.
"""
from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import pl_integrate

SPR = pl_integrate.GODOT_SPRITES

SOURCES = [
    # (id, source png, quadranti validi se non vuoti)
    ("bossdeath_rubble", "env/bossdeath_rubble.png"),
    ("bossdeath_bones", "env/bossdeath_bones.png"),
]


def quad_frames(img: Image.Image) -> list[Image.Image]:
    """4 quadranti 64x64 del 128x128 (varianti di sassi/ossa)."""
    assert img.size == (128, 128), f"atteso 128x128, trovato {img.size}"
    out = []
    for cy in range(2):
        for cx in range(2):
            q = img.crop((cx * 64, cy * 64, cx * 64 + 64, cy * 64 + 64))
            # scarta quadranti quasi vuoti (<2% pixel opachi)
            opaque = sum(1 for p in q.getdata() if p[3] > 0)
            if opaque < 64 * 64 * 0.02:
                continue
            out.append(q)
    return out


def main() -> None:
    for sid, src in SOURCES:
        src_abs = os.path.join(SPR, src)
        if not os.path.isfile(src_abs):
            print(f"[{sid}] MANCA {src_abs} — generare prima con pl_run.py static")
            sys.exit(1)
        img = Image.open(src_abs).convert("RGBA")
        frames = quad_frames(img)
        if len(frames) < 4:
            # quadranti vuoti: replica i validi fino a 4
            while len(frames) < 4 and frames:
                frames.append(frames[len(frames) % max(1, len(frames))])
        if len(frames) < 4:
            print(f"[{sid}] nessun quadrante valido")
            sys.exit(1)
        target = f"env/{sid}_sheet.png"
        out = pl_integrate.write_anim_sheet(
            target, frames, frame_px=64, feet_y=56, anchor=(32, 40))
        print(f"[{sid}] sheet 4-varianti -> {out}")
    print("[task86_integrate] completo")


if __name__ == "__main__":
    main()

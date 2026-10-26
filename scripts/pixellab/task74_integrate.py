#!/usr/bin/env python3
"""task74_integrate.py — TASK 74: integra la statua pietrificata a 64x64.

Dal frame pietrificato (petrified/statue_final.png 256x256):
  1. resize NEAREST a 64x64 (write_static: backup + mirror legacy)
  2. tocco finale deterministico "statua antica": 8-10 px di muschio
     verde-grigio desaturato alla base (stivali) — vendibile a 64px,
     non rischia il look hand-scribbled delle crepe disegnate a mano
  3. verifica bbox (atteso ~50x57, massiccio come l'alleato)
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from PIL import Image

import pl_integrate

SRC = os.path.join(HERE, "out", "knight_statue", "petrified", "statue_final.png")
TARGET_REL = "collectibles/item_knight_statue.png"

# muschio: verde-grigio desaturato (coerente col muschio dei muri Maze)
MOSS = (74, 96, 66)


def main() -> None:
    img = Image.open(SRC).convert("RGBA")

    # 1) integra (backup .bak-pre-pixellab-v2 + resize NEAREST + mirror)
    final = pl_integrate.write_static(TARGET_REL, img, (64, 64))
    print(f"integrato: {final}")

    # 2) muschio deterministico alla base (riga dei piedi ~y[54..59])
    im = Image.open(final).convert("RGBA")
    a = np.array(im)
    op = a[:, :, 3] > 10
    # trova la base del contenuto: ultima riga opaca
    last_rows = np.nonzero(op.any(axis=1))[0]
    y_feet = int(last_rows.max())
    rng = np.random.default_rng(74)
    placed = 0
    for _ in range(40):
        if placed >= 8:
            break
        x = int(rng.integers(18, 46))
        y = int(y_feet - rng.integers(0, 5))
        # solo su pixel gia' opachi (la statua), non sull'aura trasparente
        if 0 <= y < 64 and a[y, x, 3] > 10:
            # il muschio copre solo pixel di MEZZA-tonalita' (pietra esposta)
            lum = 0.299 * a[y, x, 0] + 0.587 * a[y, x, 1] + 0.114 * a[y, x, 2]
            if 70 < lum < 190:
                a[y, x, 0], a[y, x, 1], a[y, x, 2] = MOSS
                a[y, x, 3] = 255
                placed += 1
    Image.fromarray(a).save(final)
    pl_integrate._sync_mirror(TARGET_REL, final)
    print(f"muschio: {placed} px alla base")

    # 3) verifica
    a2 = np.array(Image.open(final).convert("RGBA"))
    ys, xs = np.nonzero(a2[:, :, 3] > 10)
    print(f"contenuto finale 64x64: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}] "
          f"({xs.max()-xs.min()+1}x{ys.max()-ys.min()+1}) — alleato ~50x55")


if __name__ == "__main__":
    main()

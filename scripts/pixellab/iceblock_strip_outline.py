#!/usr/bin/env python3
"""Task 65b — strip outline dall'iceblock PixelLab (tentativo 2).

PROBLEMA: anche con outline "lineless" la generazione produce un anello
scuro (bordo "sticker") attorno alla massa di ghiaccio. L'overlay deve
FONDERSI col nemico congelato (draw a modulate 0.45 in Enemy.gd), quindi
un bordo netto scuro/chiaro e' inaccettabile (VLM FAIL 2 volte).

SOLUZIONE deterministica e gratuita (pattern post-processing PIL della
pipeline): erosione della maschera alpha di 3px (rimuove l'anello scuro
perimetrale) + feather 1.5px (bordo morbido che si fonde). L'interno —
ghiaccio azzurro con bolle e scintille — resta intatto.

Uso: python3 iceblock_strip_outline.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import pl_integrate
import pl_qa

SRC = os.path.join(HERE, "out", "effect_iceblock", "base.png")
TARGET_REL = "effect_iceblock.png"
ERODE_KERNEL = 7      # MinFilter 7x7 ~ erosione 3px
FEATHER_BLUR = 1.5    # px di sfumatura del nuovo bordo


def main() -> int:
    img = Image.open(SRC).convert("RGBA")

    # 1) pulizia sfondo (come pl_run: flood dai bordi + frangia)
    img = pl_integrate.remove_solid_background(img, tol=26)

    # 2) maschera binaria
    alpha = img.getchannel("A").point(lambda a: 255 if a > 100 else 0)

    # 3) erosione: rimuove l'anello perimetrale (spesso ~2-4px)
    alpha = alpha.filter(ImageFilter.MinFilter(ERODE_KERNEL))

    # 4) feather: bordo morbido che si fonde col mostro sotto
    alpha = alpha.filter(ImageFilter.GaussianBlur(FEATHER_BLUR))

    # 5) rimonta il canale alpha (i colori interni restano quelli generati)
    out = img.copy()
    out.putalpha(alpha)

    # 6) riduzione palette (coerente con la pipeline)
    n_cols = len({(p[0], p[1], p[2]) for p in out.getdata() if p[3] > 0})
    if n_cols > 96:
        out = pl_integrate.reduce_palette(out, 96)
    n_cols = len({(p[0], p[1], p[2]) for p in out.getdata() if p[3] > 0})
    print(f"[iceblock] colori dopo strip-outline: {n_cols}")

    # 7) QA + integrazione (backup + dual-sync mirror)
    errors = pl_qa.qa_static(out, ref=None, max_colors=96,
                             cov=(8.0, 66.0))
    if not pl_qa.report("effect_iceblock [strip-outline]", errors):
        print("[iceblock] QA FALLITA — NON integrato")
        return 1
    final = pl_integrate.write_static(TARGET_REL, out, (128, 128))
    print(f"[iceblock] integrato -> {final}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

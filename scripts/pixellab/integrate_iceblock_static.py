#!/usr/bin/env python3
"""Task 60c — integrazione statica dell'iceblock dal base.png gia' pagato.

L'animazione animate-v3 ha fallito la QA 2 volte (frame troppo statici:
il modello non muove un cubo di ghiaccio). PIVOT: cristallo STATICo
PixelLab + animazione procedurale in codice (sparkles/pulsazione), come
per i muri Task 57 (ibrido). Risparmia generazioni ed e' piu' robusto.

Uso: python3 integrate_iceblock_static.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image

import pl_integrate
import pl_qa

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "out", "effect_iceblock", "base.png")
TARGET = "effect_iceblock.png"   # root sprites (convenzione effect_*)

img = Image.open(BASE).convert("RGBA")
img = pl_integrate.remove_solid_background(img, tol=26)
n_cols = len({(p[0], p[1], p[2]) for p in img.getdata() if p[3] > 0})
print(f"[iceblock] colori dopo bg-remove: {n_cols}")
if n_cols > 96:
    img = pl_integrate.reduce_palette(img, 96)
    print(f"[iceblock] palette ridotta a 96")

errors = pl_qa.qa_static(img, ref=None, max_colors=96, cov=(8.0, 60.0))
ok = pl_qa.report("effect_iceblock [static-pivot]", errors)
if not ok:
    print("[iceblock] QA FALLITA — NON integrato")
    sys.exit(1)

final = pl_integrate.write_static(TARGET, img, (128, 128))
print(f"[iceblock] integrato -> {final}")

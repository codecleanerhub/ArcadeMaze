#!/usr/bin/env python3
"""gen_portal_anchor.py — TASK 73: anchor TONDO per il portale magico.

Genera il color_image anchor della ricetta defs_task73.magic_portal.
PERCHE': la ricetta Task 65 uso' come anchor il vecchio sheet PIATTO
(galassia orizzontale 60x33) e l'anchor ha trascinato la forma → il
vortice rigenerato restava una mezzaluna che l'utente leggeva come
"portale tagliato a meta'" (stessa lezione del Task 72: l'anchor del
masso trascinava la texture). Questo anchor e' un CERCHIO COMPLETO:
anello di pietra scura + vortice viola/ciano a 3 bracci + nucleo
bianco + scintille, 238x238 centrato con margini 9px su canvas 256.

Rigenerare (deterministico, 0 generazioni PixelLab):
  python3 scripts/pixellab/gen_portal_anchor.py
"""
from PIL import Image, ImageDraw
import math
import os

W = 256
S = 0.90          # scala: margini >= 8px su ogni lato
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "out", "magic_portal", "anchor_round.png")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
cx, cy = W // 2, W // 2

# --- anello di pietra esterno: grigio pietra scuro ---
for r in range(int(124 * S), int(103 * S), -1):
    t = (r - 104) / 20.0
    g = int(52 + 30 * t)
    col = (g, g - 6, g + 12, 255)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=1)

# tacche runiche viola incise sull'anello (8, alternate)
for i in range(8):
    a = (i / 8.0) * math.tau + 0.3
    x = cx + math.cos(a) * 114 * S
    y = cy + math.sin(a) * 114 * S
    d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(120, 70, 190, 255))

# --- vortice interno: 3 bracci di spirale viola/ciano verso il centro ---
RS = int(102 * S)
d.ellipse([cx - RS, cy - RS, cx + RS, cy + RS], fill=(28, 16, 48, 255))

for arm in range(3):
    a0 = (arm / 3.0) * math.tau
    pts = []
    for step in range(56):
        t = step / 55.0                      # 0 = esterno, 1 = centro
        r = 96.0 * S * (1.0 - t) + 8.0
        ang = a0 + 1.9 * math.tau * t        # ~2 giri di avvolgimento
        x = cx + math.cos(ang) * r
        y = cy + math.sin(ang) * r
        pts.append((x, y))
    for i in range(len(pts) - 1):
        wdt = max(2, int(11 * (1.0 - i / len(pts))) + 2)
        t = i / len(pts)
        if t < 0.5:
            col = (150, 80, 230, 255)
        else:
            col = (90, 190, 240, 255)
        d.line([pts[i], pts[i + 1]], fill=col, width=wdt)

# --- nucleo luminoso centrale ---
d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=(210, 170, 250, 255))
d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=(250, 245, 255, 255))

# --- scintille attorno al bordo esterno (fuori anello) ---
for i in range(10):
    a = (i / 10.0) * math.tau + 0.15
    r = 118.0
    x = cx + math.cos(a) * r
    y = cy + math.sin(a) * r
    d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(170, 120, 250, 255))

img.save(OUT)

import numpy as np
a = np.array(img)
ys, xs = np.nonzero(a[:, :, 3] > 10)
print(f'anchor salvato: {OUT}')
print(f'bbox contenuto: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}] '
      f'(w={xs.max()-xs.min()+1} h={ys.max()-ys.min()+1}) — tondo, margini 9px')

#!/usr/bin/env python3
"""gen_knight_statue_anchor.py — TASK 74: anchor PIETRA per la statua
del cavaliere.

PERCHE' (lezione Task 73, 3a volta): l'utente vuole la statua "piu'
simile alla sua versione attivata" (il knight_ally del Task 71). L'anchor
trascina forma E palette -> anchor = frame 3 del knight_ally_sheet (il
piu' statuario: eretto, gambe quasi unite, spada rilassata al fianco,
mantello caduto naturale) convertito in PIETRA.

Conversione: luminanza per-percentili -> rampa pietra a 6 gradini
(ombre blu-grigio desaturato, mezzi grigio-beige caldi, luci bianco
sporco ocra — consiglio VLM: pietra ≠ grigio morto). L'alpha resta.

Output: out/knight_statue/anchor_stone.png (256x256, frame 64 -> 4x
NEAREST, centrato) — pronto come color_image di defs_task74.

Rigenerare (deterministico, 0 generazioni PixelLab):
  python3 scripts/pixellab/gen_knight_statue_anchor.py
"""
from PIL import Image
import numpy as np
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "godot", "assets", "sprites",
                   "knight_ally_sheet.png")
OUT = os.path.join(HERE, "out", "knight_statue", "anchor_stone.png")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

FRAME = 3  # il piu' statuario del walk cycle (VLM: "at attention")

# rampa pietra: dal piu' scuro al piu' chiaro
RAMP = [
    (54, 52, 68),    # ombra profonda: blu-grigio desaturato
    (84, 82, 98),    # ombra
    (118, 114, 108),  # mezzo: grigio-beige caldo
    (150, 146, 138),  # mezzo-chiaro
    (182, 178, 168),  # luce
    (214, 210, 198),  # luce max: bianco sporco ocra
]

sheet = Image.open(SRC).convert("RGBA")
frame = sheet.crop((FRAME * 64, 0, (FRAME + 1) * 64, 64))
a = np.array(frame)

alpha = a[:, :, 3]
opaque = alpha > 10
lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2])

# soglie per-percentili sull'area OPACA (equal-area -> la struttura
# d'ombreggiatura dell'armatura resta leggibile nella pietra)
vals = np.sort(lum[opaque])
n = len(vals)
thr = [vals[int(q * (n - 1))] for q in (1/6, 2/6, 3/6, 4/6, 5/6)]

stone = np.zeros_like(a)
li = np.digitize(lum, thr)  # 0..5
for k, col in enumerate(RAMP):
    sel = opaque & (li == k)
    stone[sel, 0] = col[0]
    stone[sel, 1] = col[1]
    stone[sel, 2] = col[2]
stone[:, :, 3] = np.where(opaque, 255, 0)

# canvas 256x256 con il frame 64 -> 4x NEAREST, centrato
big = Image.fromarray(stone).resize((256, 256), Image.NEAREST)
canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
canvas.paste(big, (0, 0), big)
canvas.save(OUT)

arr = np.array(canvas)
ys, xs = np.nonzero(arr[:, :, 3] > 10)
print(f'anchor salvato: {OUT}')
print(f'contenuto: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}] '
      f'({xs.max()-xs.min()+1}x{ys.max()-ys.min()+1} su 256)')

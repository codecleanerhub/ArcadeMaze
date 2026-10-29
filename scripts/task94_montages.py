#!/usr/bin/env python3
"""Task 94 — montaggi di verifica dalle sequenze catturate."""
from PIL import Image, ImageDraw
import glob

D = "/home/z/my-project/download/"


def seq(prefix):
    fs = sorted(glob.glob(D + prefix + "*.png"))
    return [Image.open(f).convert("RGB") for f in fs]


def grid(frames, idxs, cols, cell=(460, 300), labels=None, out=""):
    im = Image.new("RGB", (cols * cell[0] + 10, cell[1] + 26), (25, 22, 18))
    d = ImageDraw.Draw(im)
    for k, fi in enumerate(idxs):
        if fi >= len(frames):
            continue
        f = frames[fi].resize(cell, Image.LANCZOS)
        x = 5 + (k % cols) * cell[0]
        y = 22
        im.paste(f, (x, y))
        lab = labels[k] if labels else f"frame {fi}"
        d.text((x + 4, 4), lab, fill=(240, 240, 240, 255))
    im.save(D + out)
    print("saved", D + out, im.size)


# hell: apertura (f~35), pieno (f~60), chiusura (f~82)
hell = seq("task94_hell")
grid(hell, [35, 60, 82], 3, out="task94_hell_montage.png",
     labels=["hell t~1.2s apertura", "hell t~2.0s risucchio", "hell t~2.7s chiusura"])

# soul (LICH, anello runico verde)
soul = seq("task94_soul")
grid(soul, [35, 60, 82], 3, out="task94_soul_montage.png",
     labels=["soul t~1.2s", "soul t~2.0s", "soul t~2.7s"])

# blades (livello 58, 5 lame): frame a meta' corsa
blades = seq("task94_blades")
grid(blades, [30, 45, 60, 75], 4, cell=(460, 300), out="task94_blades_montage.png",
     labels=["lame f30", "lame f45", "lame f60", "lame f75"])

# hazards: crepa (early) + fossa aperta (late)
hz_e = Image.open(D + "hazards_lvl12_early.png").convert("RGB")
hz_l = Image.open(D + "hazards_lvl12_late.png").convert("RGB")
im = Image.new("RGB", (2 * 640 + 12, 440), (25, 22, 18))
d = ImageDraw.Draw(im)
for k, (f, lab) in enumerate([(hz_e, "crepa (telegrafo)"), (hz_l, "fossa aperta")]):
    im.paste(f.resize((640, 420), Image.LANCZOS), (5 + k * 645, 18))
    d.text((10 + k * 645, 2), lab, fill=(240, 240, 240, 255))
im.save(D + "task94_chasm_game.png")
print("saved task94_chasm_game.png")

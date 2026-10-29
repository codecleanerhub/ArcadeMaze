#!/usr/bin/env python3
"""Task 94 — ricolorazione voragini in palette dungeon (feedback utente).

"quei blocchi blu delle fosse devono essere piu' integrati nel labirinto,
dello stesso colore... la crepa non deve stare nel blocco blu ma in un
blocco del colore coerente col labirinto."

chasm_crack.png e chasm_open.png erano tile BLU opachi (#090214, #302e5e,
#4b4b80): nel labirinto marrone/roccia spiccavano come glitch. Ricoloro
mantenendo INTATTA la geometria (crepe, rilievi, bordo): mappo il value
(max rgb) di ogni pixel sulla palette calda del pavimento del dungeon.

- crack: superficie in toni pietra calda SEMITRASPARENTE (alpha ~190-210)
  -> il gradiente reale del pavimento sotto traspare e il tile si integra
  ovunque (centro piu' chiaro, bordi piu' scuri); crepe scure opache.
- open: fossa calda opaca (vuoto quasi nero, pareti scure, bordo di pietra
  rotta piu' chiaro e leggibile).
"""
from PIL import Image, ImageDraw

D = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/hazards/"

# value-band -> (r, g, b, alpha)  [palette pavimento dungeon]
CRACK_MAP = [
    (32, (14, 10, 7, 255)),      # crepa profonda
    (56, (24, 18, 13, 240)),     # ombra crepa
    (104, (34, 28, 21, 210)),    # pietra scura
    (152, (44, 37, 28, 200)),    # pietra media
    (200, (56, 47, 36, 195)),    # pietra chiara
    (999, (72, 61, 46, 190)),    # rilievo
]
OPEN_MAP = [
    (45, (6, 4, 3, 255)),        # vuoto
    (75, (18, 13, 10, 255)),     # parete interna
    (110, (44, 37, 29, 255)),    # base bordo rotto
    (160, (66, 56, 43, 250)),    # pietra bordo
    (999, (92, 80, 62, 245)),    # luce bordo
]


def remap(src: str, dst: str, table) -> None:
    im = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", im.size)
    sp, op = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            v = max(r, g, b)
            for thr, col in table:
                if v < thr:
                    op[x, y] = col
                    break
    out.save(dst)
    print("ricolorato:", dst)


remap(D + "chasm_crack.png", D + "chasm_crack.png", CRACK_MAP)
remap(D + "chasm_open.png", D + "chasm_open.png", OPEN_MAP)

# ---- confronto prima/dopo su pavimento simulato (per QA) ----
import subprocess

before = subprocess.run(
    ["git", "show", "HEAD:godot/assets/sprites/hazards/chasm_crack.png"],
    cwd="/home/z/my-project/ArcadeMaze", capture_output=True).stdout
import io
b_im = Image.open(io.BytesIO(before)).convert("RGBA")
before2 = subprocess.run(
    ["git", "show", "HEAD:godot/assets/sprites/hazards/chasm_open.png"],
    cwd="/home/z/my-project/ArcadeMaze", capture_output=True).stdout
b2_im = Image.open(io.BytesIO(before2)).convert("RGBA")

# pavimento simulato: gradiente scuro caldo + qualche crepa decorativa
W, H = 700, 150
floor = Image.new("RGBA", (W, H))
for x in range(W):
    br = 24 - int(x / W * 18)
    for y in range(H):
        floor.putpixel((x, y), (28 + br, 23 + int(br * 0.7), 18 + int(br * 0.4), 255))
d = ImageDraw.Draw(floor)
tiles = [("OLD crack", b_im), ("NEW crack", Image.open(D + "chasm_crack.png")),
         ("OLD open", b2_im), ("NEW open", Image.open(D + "chasm_open.png"))]
for i, (label, t) in enumerate(tiles):
    t64 = t.resize((64, 64), Image.NEAREST)
    x = 12 + i * 170
    floor.paste(t64, (x, 45), t64)
    d.text((x + 6, 22), label, fill=(240, 240, 240, 255))
floor.convert("RGB").save("/home/z/my-project/download/task94_chasm_recolor.png")
print("confronto: /home/z/my-project/download/task94_chasm_recolor.png")

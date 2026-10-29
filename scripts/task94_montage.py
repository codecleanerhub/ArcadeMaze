#!/usr/bin/env python3
"""Task 94 — montaggio degli asset attuali per QA visivo (VLM).

Righe: blade frames 0-3 | chasm_crack | chasm_open | vortex frames 0-3
"""
from PIL import Image, ImageDraw

H = "godot/assets/sprites/hazards/"
E = "godot/assets/sprites/env/"

tiles = []
# blade: sheet 256x64 -> 4 frame 64x64
bs = Image.open(H + "blade_wheel_sheet.png").convert("RGBA")
for i in range(4):
    tiles.append(("blade_f%d" % i, bs.crop((i * 64, 0, (i + 1) * 64, 64))))
# chasm
tiles.append(("chasm_crack", Image.open(H + "chasm_crack.png").convert("RGBA").resize((64, 64), Image.NEAREST)))
tiles.append(("chasm_open", Image.open(H + "chasm_open.png").convert("RGBA").resize((64, 64), Image.NEAREST)))
# vortex sheet 256x64 -> 4 frame
vs = Image.open(E + "bossdeath_vortex_sheet.png").convert("RGBA")
for i in range(4):
    tiles.append(("vortex_f%d" % i, vs.crop((i * 64, 0, (i + 1) * 64, 64))))

cell = 72
cols = len(tiles)
W = cell * cols + 10
im = Image.new("RGBA", (W, cell + 26), (40, 38, 34, 255))
d = ImageDraw.Draw(im)
for i, (name, t) in enumerate(tiles):
    x = 5 + i * cell
    im.paste(t, (x + 4, 20), t)
    d.text((x + 2, 3), name, fill=(240, 240, 240, 255))
im.save("/home/z/my-project/download/task94_current_assets.png")
print("saved download/task94_current_assets.png", im.size)

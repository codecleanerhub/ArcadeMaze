#!/usr/bin/env python3
"""Task 94 — montaggio dei NUOVI asset PixelLab per QA VLM."""
from PIL import Image, ImageDraw

E = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/env/"
H = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/hazards/"

tiles = []
ps = Image.open(E + "bossdeath_portal_sheet.png").convert("RGBA")
for i in range(4):
    tiles.append(("portal_f%d" % i, ps.crop((i * 128, 0, (i + 1) * 128, 128)).resize((96, 96), Image.NEAREST)))
rs = Image.open(E + "bossdeath_ring_sheet.png").convert("RGBA")
for i in range(4):
    tiles.append(("ring_f%d" % i, rs.crop((i * 128, 0, (i + 1) * 128, 128)).resize((96, 96), Image.NEAREST)))
bs = Image.open(H + "blade_sharp_sheet.png").convert("RGBA")
for i in range(4):
    t = bs.crop((i * 64, 0, (i + 1) * 64, 64)).resize((96, 96), Image.NEAREST)
    tiles.append(("blade_f%d" % i, t))

cell = 104
cols = len(tiles)
im = Image.new("RGBA", (cell * cols + 8, cell + 24), (40, 38, 34, 255))
d = ImageDraw.Draw(im)
for i, (name, t) in enumerate(tiles):
    x = 4 + i * cell
    im.paste(t, (x + 4, 20), t)
    d.text((x + 2, 3), name, fill=(240, 240, 240, 255))
im.save("/home/z/my-project/download/task94_new_assets.png")
print("saved", im.size)

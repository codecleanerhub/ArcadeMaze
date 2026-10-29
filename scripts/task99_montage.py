#!/usr/bin/env python3
"""Task 99 — montaggio degli asset PixelLab del Level Up per QA VLM."""
from PIL import Image, ImageDraw

S = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/skills/"

tiles = []
ids = ["energy", "stamina", "jump", "firepower",
       "magazine", "swiftness", "luck", "regen"]
for i in ids:
    t = Image.open(S + "skill_%s.png" % i).convert("RGBA")
    tiles.append((i, t.resize((96, 96), Image.NEAREST)))

bolt = Image.open(S + "levelup_bolt_sheet.png").convert("RGBA")
for i in range(4):
    tiles.append(("bolt_f%d" % i, bolt.crop((i * 64, 0, (i + 1) * 64, 64)).resize((96, 96), Image.NEAREST)))

corner = Image.open(S + "levelup_corner.png").convert("RGBA")
tiles.append(("corner", corner.resize((96, 96), Image.NEAREST)))

title = Image.open(S + "levelup_title.png").convert("RGBA")

cell = 104
cols = len(tiles)
im = Image.new("RGBA", (cell * cols + 8, cell + 24 + 110), (40, 38, 34, 255))
d = ImageDraw.Draw(im)
for i, (name, t) in enumerate(tiles):
    x = 4 + i * cell
    im.paste(t, (x + 4, 20), t)
    d.text((x + 2, 3), name, fill=(240, 240, 240, 255))
# scritta in basso, scalata x2
tw = title.size[0] * 2
im.paste(title.resize((tw, title.size[1] * 2), Image.NEAREST),
         ((im.size[0] - tw) // 2, cell + 30), title.resize((tw, title.size[1] * 2), Image.NEAREST))
d.text((4, cell + 6), "levelup_title x2", fill=(240, 240, 240, 255))
im.save("/home/z/my-project/download/task99_assets.png")
print("saved", im.size)

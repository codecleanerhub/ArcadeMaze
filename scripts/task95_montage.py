#!/usr/bin/env python3
"""Task 95 — montaggio prima/dopo dei 3 nemici rigenerati (+ riferimento)."""
from PIL import Image, ImageDraw

G = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/"
O = "/home/z/my-project/ArcadeMaze/scripts/pixellab/out/"

ids = [("monster_007", "WITCH (strega)"), ("monster_044", "LOST_SOUL"),
       ("monster_031", "GIBBERING_MOUTHER")]
ref = ("monster_021", "ZOMBIE (riferimento full-body)")

cell = 200  # 4 frame a 140px + label
im = Image.new("RGB", (cell * 6 + 12, cell * 4 + 90), (30, 27, 22))
d = ImageDraw.Draw(im)
d.text((10, 4), "TASK 95 — rigenerazione corpo completo: VECCHIO (mezzo busto) vs NUOVO (PixelLab full body)", fill=(240, 240, 240, 255))

for row, (mid, label) in enumerate(ids + [ref]):
    y = 30 + row * (cell + 8)
    # vecchio (se rigenerato: OLD in staging; per il riferimento: sheet attuale = stesso)
    old_p = O + f"task95_{mid}/OLD_sheet.png" if mid != ref[0] else G + f"{mid}_sheet.png"
    new_p = G + f"{mid}_sheet.png"
    d.text((10, y + 2), label, fill=(255, 220, 120))
    old = Image.open(old_p).convert("RGBA")
    for f in range(4):
        t = old.crop((f * 64, 0, (f + 1) * 64, 64)).resize((140, 140), Image.NEAREST)
        bg = Image.new("RGB", (150, 150), (52, 46, 40))
        bg.paste(t, (5, 5), t)
        im.paste(bg, (10 + f * 150, y + 22))
    new = Image.open(new_p).convert("RGBA")
    for f in range(4):
        t = new.crop((f * 64, 0, (f + 1) * 64, 64)).resize((140, 140), Image.NEAREST)
        bg = Image.new("RGB", (150, 150), (46, 52, 40))
        bg.paste(t, (5, 5), t)
        im.paste(bg, (10 + 640 + f * 150, y + 22))
d.text((10, y + 22 + 152), "<-- frame 1-4 VECCHIO (sfondo caldo) | frame 1-4 NUOVO (sfondo verde) -->", fill=(180, 180, 180))

im.save("/home/z/my-project/download/task95_before_after.png")
print("saved /home/z/my-project/download/task95_before_after.png", im.size)

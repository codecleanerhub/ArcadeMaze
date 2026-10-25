#!/usr/bin/env python3
"""Task 53: contact sheet dei 15 item rigenerati (vecchio vs nuovo)."""
from PIL import Image
import os

BASE = "/home/z/my-project/ArcadeMaze/godot/assets/sprites"
ITEMS = [
    ("collectibles/item_chalice.png", "chalice"),
    ("collectibles/item_dynamite.png", "dynamite"),
    ("collectibles/item_hammer.png", "hammer"),
    ("collectibles/item_knight_statue.png", "knight"),
    ("collectibles/item_medikit.png", "medikit"),
    ("collectibles/item_mine.png", "mine"),
    ("collectibles/item_potion.png", "potion"),
    ("collectibles/item_scepter.png", "scepter"),
    ("collectibles/item_speedboots.png", "boots"),
    ("collectibles/item_unicorn_statue.png", "unicorn"),
    ("treasures/treasure_chest.png", "chest"),
    ("treasures/treasure_crown.png", "crown"),
    ("treasures/treasure_cup.png", "cup"),
    ("treasures/treasure_gem.png", "gem"),
    ("treasures/treasure_gold.png", "gold"),
]

CELL = 150  # cella per item (128 sprite + margine)
COLS = 5
ROWS = (len(ITEMS) + COLS - 1) // COLS

# sfondo scacchiera per la trasparenza
sheet = Image.new("RGB", (COLS * CELL * 2, ROWS * CELL), (24, 20, 28))
px = sheet.load()
W, H = sheet.size
for y in range(H):
    for x in range(W):
        if (x // 25 + y // 25) % 2:
            px[x, y] = (40, 36, 44)

for i, (rel, _) in enumerate(ITEMS):
    r, c = divmod(i, COLS)
    # colonna sinistra = VECCHIO (dal backup), destra = NUOVO
    old_path = os.path.join(BASE, rel + ".bak-pre-pixellab-v2")
    new_path = os.path.join(BASE, rel)
    for slot, path in ((0, old_path), (1, new_path)):
        if not os.path.isfile(path):
            continue
        im = Image.open(path).convert("RGBA")
        im.thumbnail((128, 128), Image.NEAREST)
        x0 = c * CELL * 2 + slot * CELL + (CELL - im.size[0]) // 2
        y0 = r * CELL + (CELL - im.size[1]) // 2
        sheet.paste(im, (x0, y0), im)

out = "/home/z/my-project/download/task53_items_contact_sheet.png"
os.makedirs(os.path.dirname(out), exist_ok=True)
sheet.save(out, "PNG")
print(f"contact sheet: {out} ({sheet.size}) — sinistra=vecchio, destra=nuovo")

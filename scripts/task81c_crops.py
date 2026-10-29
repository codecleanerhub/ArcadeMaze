#!/usr/bin/env python3
"""task81c_crops.py — crop per la verifica VLM (TASK 81c).

Ritaglia attorno alle POSIZIONI dei lenzuoli (dump CAP81) e ai tesori
(gemma blu / rubino rosso vs corona) dalle screenshot shot_task81.
"""
from PIL import Image

DOWNLOAD = "/home/z/my-project/download/"
OUT = "/home/z/my-project/download/"

# posizioni dai dump CAP81 (ghosts: [x, y] in pixel schermo)
GHOSTS = {
    "task81_l2_ghosts_arms.png": [
        ("white", (1568, 553)),
        ("red", (1440, 681)),
    ],
    "task81_l8_ghosts_arms.png": [
        ("white", (1118, 880)),
        ("red", (1502, 752)),
        ("green", (416, 558)),
    ],
}

# tesori (cella -> centro pixel), dalla stessa run
TREASURES = {
    "task81_l2_ghosts_arms.png": [
        ("gem_blue", (19 * 64 + 32, 80 + 2 * 64 + 32)),
        ("crown_gold", (15 * 64 + 32, 80 + 4 * 64 + 32)),
        ("ruby_red", (16 * 64 + 32, 80 + 11 * 64 + 32)),
    ],
}


def crop_around(img, cx, cy, half, out_path):
    box = (max(0, cx - half), max(0, cy - half),
           min(img.width, cx + half), min(img.height, cy + half))
    img.crop(box).save(out_path)
    print("salvo", out_path, box)


def main():
    for fname, ghosts in GHOSTS.items():
        img = Image.open(DOWNLOAD + fname).convert("RGB")
        for color, (x, y) in ghosts:
            tag = "l8" if "l8" in fname else "l2"
            crop_around(img, x, y, 140, OUT + f"crop81c_ghost_{tag}_{color}.png")
    for fname, treasures in TREASURES.items():
        img = Image.open(DOWNLOAD + fname).convert("RGB")
        for name, (x, y) in treasures:
            crop_around(img, x, y, 90, OUT + f"crop81c_treasure_{name}.png")


if __name__ == "__main__":
    main()

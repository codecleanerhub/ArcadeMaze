#!/usr/bin/env python3
"""
generate_sprites_extra.py - Genera gli sprite mancanti:
1. 7 boss mancanti (boss_021, 023, 024, 025, 026, 027, 028)
2. 2 player (player1 = esploratore maschio, player2 = esploratrice femmina)

Strategia: 1 PNG 1024x1024 per entita' via z-ai, poi ridimensiona a 384x256
+ palette 16 colori + metadata JSON. Delay 15s tra chiamate per rate limit.
"""
import os
import sys
import json
import time
import subprocess
from pathlib import Path
from PIL import Image
import numpy as np

OUTPUT_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
TEMP_DIR = Path("/tmp/sprite_gen")
FRAME_W, FRAME_H = 64, 64
COLUMNS, ROWS = 6, 4

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Entita' da generare (7 boss + 2 player = 9)
ENTITIES = [
    ("boss_021", "ghoul lord, necromancer aura, bone crown, commanding pose"),
    ("boss_023", "spectral alpha wolf, larger, mane of smoke, howling stance"),
    ("boss_024", "cult herald, ornate robes, summoning staff, minion sigils"),
    ("boss_025", "colossal mimic, shifting form, treasure chest motifs, huge maw"),
    ("boss_026", "rat king, bone crown, swarm motif, regal hunched posture"),
    ("boss_027", "supreme swamp witch, larger potions, animated vines, crown of reeds"),
    ("boss_028", "twilight knight, shield absorbing light, lance, imposing helm"),
    ("player1", "brave male adventurer explorer with fedora hat, leather jacket, whip, pistol, fantasy hero"),
    ("player2", "brave female adventurer explorer with ponytail, leather vest, crossbow, fantasy heroine"),
]

ANIMS = {"idle": {"row":0,"frames":4,"frameDuration":200},
         "walk": {"row":1,"frames":6,"frameDuration":100},
         "attack": {"row":2,"frames":6,"frameDuration":100},
         "death": {"row":3,"frames":6,"frameDuration":120}}

def build_prompt(desc):
    return (
        f"Pixel art spritesheet 6x4 grid of 64x64 frames. "
        f"16-color palette, fantasy horror, transparent background. "
        f"Character: {desc}. "
        f"Row 1: idle (4 frames). Row 2: walk (6 frames). "
        f"Row 3: attack (6 frames). Row 4: death (6 frames). "
        f"Crisp outlines, gothic mood. No text, no UI."
    )

def generate(prompt, output):
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output), "-s", "1024x1024"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        print(f"  ERR: {r.stderr[:200]}")
        return False
    return output.exists()

def process(raw, cid):
    img = Image.open(raw).convert("RGBA")
    img = img.resize((COLUMNS*FRAME_W, ROWS*FRAME_H), resample=Image.NEAREST)
    arr = np.array(img)
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    out = np.dstack([new_rgb, arr[..., 3]])
    Image.fromarray(out.astype('uint8'), 'RGBA').save(OUTPUT_DIR / f"{cid}_sheet.png")
    print(f"  OK {cid}")

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    success = 0
    for i, (cid, desc) in enumerate(ENTITIES):
        sheet = OUTPUT_DIR / f"{cid}_sheet.png"
        if sheet.exists():
            print(f"[SKIP] {cid}")
            success += 1
            continue
        if i > 0:
            print(f"  (attesa 15s per rate limit...)")
            time.sleep(15)
        print(f"[GEN] {cid}...")
        prompt = build_prompt(desc)
        raw = TEMP_DIR / f"{cid}_raw.png"
        if not generate(prompt, raw):
            print(f"  retry con attesa 60s...")
            time.sleep(60)
            if not generate(prompt, raw):
                continue
        process(raw, cid)
        meta = {"image": f"{cid}_sheet.png", "frameWidth": FRAME_W,
                "frameHeight": FRAME_H, "columns": COLUMNS, "rows": ROWS,
                "anchor": {"x":32,"y":56},
                "animations": {k:v for k,v in ANIMS.items()}}
        with open(OUTPUT_DIR / f"{cid}_meta.json", "w") as f:
            json.dump(meta, f, indent=2)
        success += 1
    print(f"\n=== Riepilogo: {success}/{len(ENTITIES)} ===")

if __name__ == "__main__":
    main()

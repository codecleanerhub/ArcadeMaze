#!/usr/bin/env python3
"""
generate_sprites_retry.py - Riprova le creature fallite con prompt piu' brevi.
"""
import os
import sys
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

# Creature da recuperare (prompt brevi)
RETRY = [
    ("monster_015", "demonic crow, ragged wings, metallic beak, red eyes"),
    ("monster_016", "subterranean tentacle, mucous skin, scattered eyes, writhing"),
    ("monster_017", "watchful gargoyle, stone texture, broken wings, perched stance"),
    ("monster_018", "well spirit, watery face, bubble effects, translucent"),
    ("monster_019", "cursed boar, mud-caked, tusks encrusted, low center of gravity"),
    ("monster_020", "predator fungus, glowing cap, spore puffs, stalky legs"),
    ("boss_022", "queen spider, enormous abdomen, web banners, many eyes"),
    ("boss_029", "vampire bishop, ornate vestments, draining aura, teleport flicker"),
    ("boss_030", "depths guardian, many tentacles, water shockwave, barnacle armor"),
]

def build_short_prompt(desc):
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
    import time
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    import json
    ANIMS = {"idle": {"row":0,"frames":4,"frameDuration":200},
             "walk": {"row":1,"frames":6,"frameDuration":100},
             "attack": {"row":2,"frames":6,"frameDuration":100},
             "death": {"row":3,"frames":6,"frameDuration":120}}
    success = 0
    for i, (cid, desc) in enumerate(RETRY):
        sheet = OUTPUT_DIR / f"{cid}_sheet.png"
        if sheet.exists():
            print(f"[SKIP] {cid}")
            success += 1
            continue
        # Delay tra una chiamata e l'altra per evitare rate limit 429
        if i > 0:
            print(f"  (attesa 15s per rate limit...)")
            time.sleep(15)
        print(f"[GEN] {cid}...")
        prompt = build_short_prompt(desc)
        raw = TEMP_DIR / f"{cid}_raw.png"
        if not generate(prompt, raw):
            # Se fallisce, attesa piu' lunga e riprova una volta
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
    print(f"\n=== Riepilogo retry: {success}/{len(RETRY)} ===")

if __name__ == "__main__":
    main()

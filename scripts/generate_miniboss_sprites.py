#!/usr/bin/env python3
"""
generate_miniboss_sprites.py - Genera sprite PNG 64x64 per i 17 mini-boss
dei labirinti, ispirati a mostri di LOTR e D&D.

Per ogni mini-boss genera 1 sprite 64x64 (1 frame idle):
  - miniboss_<id>_sheet.png
  - miniboss_<id>_meta.json

Usa la stessa pipeline degli sprite esistenti (boss, player, nemici):
  1. Genera immagine 1024x1024 con z-ai CLI
  2. Color keying dello sfondo (rilevato dal bordo)
  3. Ritaglia bounding box del personaggio
  4. Ridimensiona a 64x64 con LANCZOS centrato
  5. Quantizza alpha (>128 -> 255, altrimenti 0)
  6. Quantizza palette 16 colori (distanza Euclidean)
  7. Fix fringe "core-color check" (2 passate)
  8. Salva PNG 64x64 RGBA + JSON meta
"""
import os
import sys
import json
import time
import subprocess
from pathlib import Path
from PIL import Image
import numpy as np

SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
RAW_DIR = Path("/tmp/sprite_gen_miniboss")
RAW_DIR.mkdir(parents=True, exist_ok=True)

SPRITE_SIZE = 64

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# 17 mini-boss ispirati a LOTR/D&D.
# Ogni entry: (id, descrizione dettagliata del personaggio)
MINIBOSSES = [
    ("miniboss_01", "goblin chieftain, small green-skinned goblin warrior with iron armor, holding a rusty battle axe, pointed ears, tusks, menacing leader pose, dark fantasy"),
    ("miniboss_02", "cave troll, massive gray-skinned troll with rocky hide, holding a huge stone club, drooling, dim-witted brute, dark cave dweller, dark fantasy"),
    ("miniboss_03", "orc berserker, muscular green orc with war paint, holding a jagged scimitar, bloodlust eyes, tattered leather armor, brutal warrior, dark fantasy"),
    ("miniboss_04", "warg rider, dark orc warrior riding a large black wolf-like warg, holding a spear, fierce mounted warrior, dark fantasy"),
    ("miniboss_05", "uruk-hai, tall dark-skinned orc warrior with black armor, holding a curved sword, white hand mark on helmet, elite warrior, dark fantasy"),
    ("miniboss_06", "nazgul, black-robed ringwraith, hooded figure with no visible face, holding a cursed dagger, dark cape flowing, ghostly warrior, dark fantasy"),
    ("miniboss_07", "ogre brute, huge fat ogre with gray skin, holding a heavy mace, big belly, small head with tusks, dim warrior, dark fantasy"),
    ("miniboss_08", "gnoll pack lord, hyena-headed humanoid with brown fur, holding a battle axe, laughing menacingly, tribal armor, dark fantasy"),
    ("miniboss_09", "bugbear chief, large furry goblinoid with orange-brown fur, holding a spiked chain, hairy beast warrior, dark fantasy"),
    ("miniboss_10", "minotaur, bull-headed humanoid with brown fur, holding a double-bladed axe, horned head, muscular beast warrior, dark fantasy"),
    ("miniboss_11", "wight lord, skeletal undead warrior with glowing blue eyes, holding a spectral sword, tattered armor, ghostly knight, dark fantasy"),
    ("miniboss_12", "cave giant, massive humanoid giant with rocky gray skin, holding a tree trunk club, mossy patches, primal giant, dark fantasy"),
    ("miniboss_13", "death knight, armored undead knight with skull face, holding a black longsword, dark plate armor with glowing cracks, dark fantasy"),
    ("miniboss_14", "illithid mind flayer, purple-skinned humanoid with tentacled face, holding no weapon but mind powers, dark robes, sinister psionic, dark fantasy"),
    ("miniboss_15", "ettin, two-headed giant with rocky skin, holding two clubs (one in each hand), both heads with tusks, brutish dual-headed, dark fantasy"),
    ("miniboss_16", "fomorian, deformed giant with twisted body, gray skin, holding a huge club, one eye larger than other, ugly giant, dark fantasy"),
    ("miniboss_17", "balrog cultist, dark hooded cultist with fire whip, red robes, holding a flaming whip, demonic servant, fire aura, dark fantasy"),
]


def build_prompt(desc):
    """Prompt per pixel art 8/16-bit, sprite singolo 64x64."""
    return (
        f"Pixel art character sprite, EXACT 64x64 pixels resolution. "
        f"Style: NES SNES C64 Mega Drive 8-bit 16-bit retro video game. "
        f"Limited 16-color palette, saturated colors, strong contrast. "
        f"Simple shading, minimal dithering, crisp 1-pixel outlines. "
        f"NO anti-aliasing, NO soft gradients, NO blur, NO modern effects. "
        f"Every pixel must be sharp and square. "
        f"Character: {desc}. "
        f"Full body visible from head to feet, including legs. "
        f"Single character, centered, facing right, full body visible. "
        f"Clear silhouette, readable pose, simple proportions. "
        f"Completely transparent background (RGBA alpha=0), no background color. "
        f"Fantasy horror atmosphere, dark mood, gothic. "
        f"NO text, NO UI, NO watermark, NO frame border, NO grid. "
        f"Must look like authentic retro game sprite from 1990s."
    )


def generate_image(prompt, output_path):
    """Chiama z-ai CLI per generare un'immagine 1024x1024."""
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output_path), "-s", "1024x1024"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        print(f"  ERROR z-ai: {r.stderr[:200]}")
        return False
    return output_path.exists()


def fix_fringe_core_color(arr):
    """Fix fringe 'core-color check' (2 passate)."""
    h, w = arr.shape[:2]
    for _ in range(2):
        alpha = arr[..., 3]
        opachi = alpha > 0
        bordo = np.zeros((h, w), dtype=bool)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                shifted = np.roll(np.roll(opachi, dy, axis=0), dx, axis=1)
                bordo |= (~shifted) & opachi
        bordo[0, :] = True; bordo[-1, :] = True
        bordo[:, 0] = True; bordo[:, -1] = True
        core_mask = opachi & (~bordo)
        core_colors = set()
        rgb_core = arr[core_mask][..., :3]
        for c in rgb_core:
            core_colors.add(tuple(c))
        bordo_coords = np.argwhere(bordo)
        for y, x in bordo_coords:
            c = tuple(arr[y, x, :3])
            if c not in core_colors:
                arr[y, x, 3] = 0
    return arr


def process_miniboss(mb_id, desc):
    """Genera raw AI -> sprite 64x64."""
    raw_path = RAW_DIR / f"{mb_id}_raw.png"
    if not generate_image(build_prompt(desc), raw_path):
        return False

    raw = Image.open(raw_path).convert("RGBA")
    arr = np.array(raw)
    alpha = arr[..., 3]
    has_transparency = np.sum(alpha == 0) > 1000

    if has_transparency:
        rgba = arr
    else:
        rgb = arr[..., :3].astype(int)
        border = np.concatenate([rgb[0,:,:], rgb[-1,:,:], rgb[:,0,:], rgb[:,-1,:]], axis=0)
        quantized = (border // 16) * 16
        colors, counts = np.unique(quantized, axis=0, return_counts=True)
        bg_q = colors[np.argmax(counts)]
        mask = np.all(np.abs(quantized - bg_q) <= 16, axis=1)
        bg = np.mean(border[mask], axis=0).astype(int) if mask.sum() > 0 else bg_q
        dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))
        alpha_new = np.clip((dist - 30) / 30, 0, 1) * 255
        rgba = np.dstack([arr[..., :3], alpha_new.astype(np.uint8)])

    alpha = rgba[..., 3]
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not (rows.any() and cols.any()):
        return False
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    rmin = max(0, rmin - 2); rmax = min(rgba.shape[0], rmax + 3)
    cmin = max(0, cmin - 2); cmax = min(rgba.shape[1], cmax + 3)
    rgba = rgba[rmin:rmax, cmin:cmax]

    h, w = rgba.shape[:2]
    if h == 0 or w == 0:
        return False
    img = Image.fromarray(rgba, 'RGBA')
    scale = min(SPRITE_SIZE / w, SPRITE_SIZE / h)
    new_w = max(1, int(w * scale)); new_h = max(1, int(h * scale))
    img = img.resize((new_w, new_h), resample=Image.LANCZOS)
    canvas = Image.new('RGBA', (SPRITE_SIZE, SPRITE_SIZE), (0, 0, 0, 0))
    canvas.paste(img, ((SPRITE_SIZE - new_w) // 2, (SPRITE_SIZE - new_h) // 2), img)
    final = np.array(canvas)

    alpha = final[..., 3]
    alpha_q = np.where(alpha > 128, 255, 0).astype(np.uint8)
    final[..., 3] = alpha_q

    rgb_flat = final[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb_flat[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(SPRITE_SIZE, SPRITE_SIZE, 3)
    final = np.dstack([new_rgb, final[..., 3]]).astype(np.uint8)

    final = fix_fringe_core_color(final)

    out_path = SPRITES_DIR / f"{mb_id}_sheet.png"
    Image.fromarray(final, 'RGBA').save(out_path)

    meta = {
        "image": f"{mb_id}_sheet.png",
        "frameWidth": SPRITE_SIZE, "frameHeight": SPRITE_SIZE,
        "columns": 1, "rows": 1,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": 1, "frameDuration": 200},
            "walk":   {"row": 0, "frames": 1, "frameDuration": 100},
            "attack": {"row": 0, "frames": 1, "frameDuration": 100},
            "death":  {"row": 0, "frames": 1, "frameDuration": 120}
        }
    }
    meta_path = SPRITES_DIR / f"{mb_id}_meta.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    opachi = np.sum(final[..., 3] > 0)
    print(f"  [DONE] {mb_id}: 64x64, opachi={opachi}/{SPRITE_SIZE*SPRITE_SIZE}")
    return True


def main():
    only_id = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_id = sys.argv[2]

    print(f"=== Generazione sprite PNG per 17 mini-boss (LOTR/D&D) ===")
    print(f"Totale: {len(MINIBOSSES)} mini-boss")
    print()

    success = 0
    for i, (mb_id, desc) in enumerate(MINIBOSSES):
        if only_id and mb_id != only_id:
            continue
        sheet_path = SPRITES_DIR / f"{mb_id}_sheet.png"
        if sheet_path.exists() and not only_id:
            print(f"[SKIP] {mb_id} (gia' esistente)")
            success += 1
            continue
        print(f"[GEN] {mb_id}: {desc[:60]}...")
        for attempt in range(2):
            if attempt > 0:
                print(f"  retry {attempt} (attesa 30s)...")
                time.sleep(30)
            if process_miniboss(mb_id, desc):
                success += 1
                break
        time.sleep(10)

    print()
    print(f"=== Done: {success}/{len(MINIBOSSES) if not only_id else 1} mini-boss generati ===")


if __name__ == "__main__":
    main()

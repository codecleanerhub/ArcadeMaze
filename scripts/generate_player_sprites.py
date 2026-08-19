#!/usr/bin/env python3
"""
generate_player_sprites.py - Genera sprite PNG per i 6 nuovi personaggi
giocabili (mago, orco, elfo, cavaliere, golem, drago, vampiro).

Per ogni personaggio genera 6 sprite 64x64:
  - <base>_sheet.png      (idle/stand)
  - <base>_walk0..3_sheet.png  (4 frame camminata)
  - <base>_jump_sheet.png  (salto)

Usa la stessa pipeline degli sprite esistenti:
  1. Genera immagine 1024x1024 con z-ai CLI
  2. Color keying dello sfondo (rilevato dal bordo)
  3. Ritaglia bounding box del personaggio
  4. Ridimensiona a 64x64 con LANCZOS centrato
  5. Quantizza alpha (>128 -> 255, altrimenti 0)
  6. Quantizza palette 16 colori (distanza Euclidean)
  7. Fix fringe "core-color check" (2 passate)
  8. Salva PNG 64x64 RGBA + JSON meta

I prompt descrivono personaggi fantasy ispirati a LOTR/D&D, con posa
diversa per ogni frame (idle fermo, walk0-3 passi alternati, jump in aria).
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
RAW_DIR = Path("/tmp/sprite_gen_chars")
RAW_DIR.mkdir(parents=True, exist_ok=True)

SPRITE_SIZE = 64

# Palette 16 colori OBBLIGATORIA (dal prompt originale)
PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# 6 nuovi personaggi + descrizioni dettagliate per ogni frame.
# Ogni personaggio ha 6 frame: idle, walk0, walk1, walk2, walk3, jump.
# I prompt descrivono il personaggio + la posa specifica del frame.
CHARACTERS = [
    {
        "base": "char_mage",
        "desc": "wizard mage character, long blue robe with gold trim, pointed blue cone hat with star, white beard, holding wooden staff with glowing crystal, old man",
        "poses": {
            "":      "standing idle pose, facing right, staff in right hand, robe hanging straight",
            "walk0": "walking pose frame 1, right leg forward, left leg back, robe swaying",
            "walk1": "walking pose frame 2, legs together mid-step, robe shifted",
            "walk2": "walking pose frame 3, left leg forward, right leg back, robe swaying",
            "walk3": "walking pose frame 4, legs together mid-step, robe shifted",
            "jump":  "jumping pose, legs tucked up, robe flowing upward, staff raised",
        },
    },
    {
        "base": "char_orc",
        "desc": "orc warrior character, green skin, large tusks, pointed ears, muscular build, dark leather armor, holding heavy axe, brutal warrior",
        "poses": {
            "":      "standing idle pose, facing right, axe in right hand, menacing stance",
            "walk0": "walking pose frame 1, right leg forward, left leg back, axe swaying",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, legs tucked, axe raised overhead",
        },
    },
    {
        "base": "char_elf",
        "desc": "elf ranger character, blonde hair, long pointed ears, green hooded cloak, leather armor, holding bow, agile elf",
        "poses": {
            "":      "standing idle pose, facing right, bow in left hand, graceful stance",
            "walk0": "walking pose frame 1, right leg forward, left leg back, cloak flowing",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, legs tucked, bow drawn",
        },
    },
    {
        "base": "char_knight",
        "desc": "knight warrior character, silver plate armor, helmet with visor and red plume, holding longsword, noble knight",
        "poses": {
            "":      "standing idle pose, facing right, sword in right hand, armored stance",
            "walk0": "walking pose frame 1, right leg forward, left leg back, armor clanking",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, legs tucked, sword raised",
        },
    },
    {
        "base": "char_golem",
        "desc": "stone golem character, gray rock body with cracks, glowing cyan eyes, mossy patches, bulky stone construct, no weapon, massive fists",
        "poses": {
            "":      "standing idle pose, facing right, fists at sides, rocky stance",
            "walk0": "walking pose frame 1, right leg forward, left leg back, body tilting",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, legs tucked, fists raised",
        },
    },
    {
        "base": "char_dragon",
        "desc": "dragon man character, red scales, dragon wings folded, pointed tail, horned head, holding fiery sword, half-dragon warrior",
        "poses": {
            "":      "standing idle pose, facing right, sword in right hand, wings folded",
            "walk0": "walking pose frame 1, right leg forward, left leg back, tail swaying",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, wings spread, legs tucked, sword raised",
        },
    },
    {
        "base": "char_vampire",
        "desc": "vampire lord character, pale skin, black cape with red lining, slicked black hair, fangs, noble vampire suit, holding cane",
        "poses": {
            "":      "standing idle pose, facing right, cane in left hand, cape draped",
            "walk0": "walking pose frame 1, right leg forward, left leg back, cape flowing",
            "walk1": "walking pose frame 2, legs together mid-step",
            "walk2": "walking pose frame 3, left leg forward, right leg back",
            "walk3": "walking pose frame 4, legs together mid-step",
            "jump":  "jumping pose, cape spread like wings, legs tucked",
        },
    },
]


def build_prompt(desc, pose):
    """Prompt per pixel art 8/16-bit, sprite singolo 64x64."""
    return (
        f"Pixel art character sprite, EXACT 64x64 pixels resolution. "
        f"Style: NES SNES C64 Mega Drive 8-bit 16-bit retro video game. "
        f"Limited 16-color palette, saturated colors, strong contrast. "
        f"Simple shading, minimal dithering, crisp 1-pixel outlines. "
        f"NO anti-aliasing, NO soft gradients, NO blur, NO modern effects. "
        f"Every pixel must be sharp and square. "
        f"Character: {desc}. "
        f"Pose: {pose}. "
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
    """Fix fringe 'core-color check' (2 passate).
    Trova i pixel di core (opachi NON adiacenti a trasparenti, 8 vicini).
    Per ogni pixel di BORDO (opaco adiacente a trasparente):
      - se il colore NON appare nel core -> fringe -> alpha=0
      - se appare nel core -> parte del personaggio -> lascia
    Ripeti 2 volte per cornici a 2 pixel.
    """
    h, w = arr.shape[:2]
    for _ in range(2):
        # Trova pixel di core (opachi con tutti i 8 vicini opachi)
        alpha = arr[..., 3]
        opachi = alpha > 0
        # Maschera dei pixel di bordo: opachi ma con almeno 1 vicino trasparente
        bordo = np.zeros((h, w), dtype=bool)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                shifted = np.roll(np.roll(opachi, dy, axis=0), dx, axis=1)
                bordo |= (~shifted) & opachi
        bordo[0, :] = True; bordo[-1, :] = True
        bordo[:, 0] = True; bordo[:, -1] = True
        # Insieme dei colori del core
        core_mask = opachi & (~bordo)
        core_colors = set()
        rgb_core = arr[core_mask][..., :3]
        for c in rgb_core:
            core_colors.add(tuple(c))
        # Per ogni pixel di bordo, se il colore non e' nel core -> fringe
        bordo_coords = np.argwhere(bordo)
        for y, x in bordo_coords:
            c = tuple(arr[y, x, :3])
            if c not in core_colors:
                arr[y, x, 3] = 0  # fringe -> trasparente
    return arr


def process_frame(base, frame_name, desc, pose):
    """Genera raw AI -> sprite 64x64 con trasparenza + palette + fringe fix."""
    raw_path = RAW_DIR / f"{base}_{frame_name}_raw.png"
    prompt = build_prompt(desc, pose)
    if not generate_image(prompt, raw_path):
        return False

    raw = Image.open(raw_path).convert("RGBA")
    arr = np.array(raw)
    alpha = arr[..., 3]
    has_transparency = np.sum(alpha == 0) > 1000

    if has_transparency:
        rgba = arr
    else:
        # Color keying dal bordo
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

    # Ritaglia bounding box del personaggio
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

    # Quantizza alpha: > 128 -> 255, altrimenti 0
    alpha = final[..., 3]
    alpha_q = np.where(alpha > 128, 255, 0).astype(np.uint8)
    final[..., 3] = alpha_q

    # Palette 16 colori
    rgb_flat = final[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb_flat[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(SPRITE_SIZE, SPRITE_SIZE, 3)
    final = np.dstack([new_rgb, final[..., 3]]).astype(np.uint8)

    # Fix fringe "core-color check" (2 passate)
    final = fix_fringe_core_color(final)

    # Salva PNG 64x64 (nome: <base>[_<frame>]_sheet.png)
    suffix = f"_{frame_name}" if frame_name else ""
    out_path = SPRITES_DIR / f"{base}{suffix}_sheet.png"
    Image.fromarray(final, 'RGBA').save(out_path)

    # Salva JSON meta
    meta = {
        "image": f"{base}{suffix}_sheet.png",
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
    meta_path = SPRITES_DIR / f"{base}{suffix}_meta.json"
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    opachi = np.sum(final[..., 3] > 0)
    print(f"  [DONE] {base}{suffix}: 64x64, opachi={opachi}/{SPRITE_SIZE*SPRITE_SIZE}")
    return True


def main():
    # Supporta --only <base> per testare un singolo personaggio
    only_base = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_base = sys.argv[2]

    print(f"=== Generazione sprite PNG per 6 nuovi personaggi giocabili ===")
    print(f"Personaggi: {len(CHARACTERS)}")
    print(f"Frame per personaggio: 6 (idle + walk0-3 + jump)")
    print(f"Totale sprite da generare: {len(CHARACTERS) * 6}")
    print()

    success = 0
    total = 0
    for char in CHARACTERS:
        base = char["base"]
        if only_base and base != only_base:
            continue
        print(f"[CHAR] {base}")
        for frame_name, pose in char["poses"].items():
            total += 1
            sheet_path = SPRITES_DIR / f"{base}_{frame_name}_sheet.png"
            if sheet_path.exists() and not only_base:
                print(f"  [SKIP] {base}_{frame_name} (gia' esistente)")
                success += 1
                continue
            # Retry logic
            for attempt in range(2):
                if attempt > 0:
                    print(f"  retry {attempt} (attesa 30s)...")
                    time.sleep(30)
                if process_frame(base, frame_name, char["desc"], pose):
                    success += 1
                    break
            # Rate limit tra frame
            time.sleep(10)
        # Pausa piu' lunga tra personaggi
        time.sleep(15)

    print()
    print(f"=== Done: {success}/{total} sprite generati ===")


if __name__ == "__main__":
    main()

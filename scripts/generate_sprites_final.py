#!/usr/bin/env python3
"""
generate_sprites_final.py - Genera sprite SINGOLI 64x64 con pixel art vero.

Strategia (basata sul prompt dell'utente):
- Sprite singoli 64x64 (NON spritesheet 3x4)
- Sfondo trasparente RGBA esplicito
- Palette 16 colori precisa
- Stile NES/SNES/C64/Mega Drive
- Smoothing disattivato in SFML (setSmooth(false))
- Scale x4 a runtime (64->256) con pixel netti
- Bob effect per animazione invece di frame multipli

Vantaggi:
1. L'AI genera 1 immagine singola invece di 12 frame (molto piu facile)
2. Se il sfondo e' trasparente, niente color keying necessario
3. Coerenza: tutti gli sprite hanno stesso stile e dimensione

Output: 31 sprite PNG 64x64 RGBA in assets/sprites/
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
RAW_DIR = Path("/tmp/sprite_gen_final")
RAW_DIR.mkdir(parents=True, exist_ok=True)

SPRITE_SIZE = 64  # sprite singolo 64x64

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Tutte le creature (31 totali: 19 mostri + 10 boss + 2 player)
CREATURES = [
    # 19 mostri
    ("monster_001", "undead ghoul monster, rotten green skin, glowing red eyes, tattered clothes, hunched posture"),
    ("monster_002", "abyssal spider, dark black armored carapace, glowing red eyes, dark gray legs, dark colors only, no light background"),
    ("monster_003", "spectral wolf, smoky gray fur, glowing green eyes, tattered collar"),
    ("monster_004", "corrupted cultist, hooded dark purple robe, runic tattoos, ritual dagger"),
    ("monster_005", "mimic treasure chest, mouth full of teeth, brown leather straps, dark wood"),
    ("monster_006", "giant rat, matted dark brown fur, rotten yellow teeth, scavenger posture"),
    ("monster_007", "swamp witch, pointed dark black hat, potion vials, greenish skin"),
    ("monster_008", "skeleton lancer, rusted armor, broken spear, hollow eye sockets"),
    ("monster_009", "creeping shadow, amorphous dark form, smoky tendrils, no legs"),
    ("monster_010", "bone golem, massive ribcage, clacking joints, skull head"),
    ("monster_011", "ash serpent, dark gray smoky scales, ember orange eyes, sinuous body, dark muted colors only"),
    ("monster_012", "damned knight, blackened armor, ember cracks, tattered cape"),
    ("monster_013", "mad wizard, glowing eyes, torn blue robes, floating scrolls"),
    ("monster_015", "demonic crow, ragged black wings, metallic beak, red eyes"),
    ("monster_016", "subterranean tentacle, mucous green skin, scattered eyes, writhing"),
    ("monster_017", "watchful gargoyle, gray stone texture, broken wings, perched stance"),
    ("monster_018", "well spirit, watery blue face, bubble effects, translucent"),
    ("monster_019", "cursed boar, mud-caked brown fur, encrusted tusks, low stance"),
    ("monster_020", "predator fungus creature, dark purple and dark brown cap, glowing red eyes, dark green stalky legs, dark muted colors only, no light or bright colors"),
    # 10 boss
    ("boss_021", "ghoul lord king, bone crown, necromancer aura, commanding pose"),
    ("boss_022", "queen spider, enormous abdomen, web banners, many glowing eyes"),
    ("boss_023", "spectral alpha wolf, larger, mane of smoke, howling stance"),
    ("boss_024", "cult herald, ornate red robes, summoning staff, minion sigils"),
    ("boss_025", "colossal mimic, shifting treasure chest form, huge maw full of teeth"),
    ("boss_026", "rat king, bone crown, swarm of rats, regal hunched posture"),
    ("boss_027", "supreme swamp witch, larger hat, animated vines, crown of reeds"),
    ("boss_028", "twilight knight, dark armor absorbing light, lance, imposing helm"),
    ("boss_029", "vampire bishop, ornate vestments, draining aura, pale face"),
    ("boss_030", "depths guardian, many tentacles, water shockwave, barnacle armor"),
    # 2 player
    ("player1", "small full body character sprite, adventurer hero with brown fedora hat, brown leather jacket, dark pants, brown boots, holding pistol, entire body from head to feet visible, small proportions, standing full body pose, NOT a portrait, NOT bust only"),
    ("player2", "small full body character sprite, female adventurer heroine with long blonde ponytail, green leather vest, dark pants, brown boots, holding crossbow, entire body from head to feet visible, small proportions, standing full body pose, NOT a portrait, NOT bust only"),
]

def build_prompt(desc):
    """Prompt specifico per pixel art vero 8/16-bit, sprite singolo 64x64."""
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
        print(f"  ERROR: {r.stderr[:200]}")
        return False
    return output_path.exists()

def process_sprite(creature_id, desc):
    """Genera raw AI -> sprite 64x64 con trasparenza."""
    raw_path = RAW_DIR / f"{creature_id}_raw.png"
    if not generate_image(build_prompt(desc), raw_path):
        return False

    # Carica il raw
    raw = Image.open(raw_path).convert("RGBA")
    arr = np.array(raw)

    # Verifica se ha gia' trasparenza (alpha)
    alpha = arr[..., 3]
    has_transparency = np.sum(alpha == 0) > 1000

    if has_transparency:
        # L'AI ha generato con sfondo trasparente: usa diretto
        print(f"  [OK] {creature_id}: sfondo gia' trasparente")
        rgba = arr
    else:
        # Sfondo opaco: applica color keying
        # Rileva sfondo dai 4 angoli
        rgb = arr[..., :3].astype(int)
        corners = [rgb[0,0], rgb[0,-1], rgb[-1,0], rgb[-1,-1]]
        # Trova il colore piu' frequente tra i pixel del bordo
        border = np.concatenate([rgb[0,:,:], rgb[-1,:,:], rgb[:,0,:], rgb[:,-1,:]], axis=0)
        quantized = (border // 16) * 16
        colors, counts = np.unique(quantized, axis=0, return_counts=True)
        bg_q = colors[np.argmax(counts)]
        mask = np.all(np.abs(quantized - bg_q) <= 16, axis=1)
        bg = np.mean(border[mask], axis=0).astype(int) if mask.sum() > 0 else bg_q

        dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))
        alpha_new = np.clip((dist - 30) / 30, 0, 1) * 255
        rgba = np.dstack([arr[..., :3], alpha_new.astype(np.uint8)])
        print(f"  [OK] {creature_id}: sfondo {tuple(bg)} rimosso via color keying")

    # Ritaglia al bounding box del personaggio
    alpha = rgba[..., 3]
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if rows.any() and cols.any():
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        rmin = max(0, rmin - 2); rmax = min(rgba.shape[0], rmax + 3)
        cmin = max(0, cmin - 2); cmax = min(rgba.shape[1], cmax + 3)
        rgba = rgba[rmin:rmax, cmin:cmax]

    # Ridimensiona a 64x64 con LANCZOS centrato su canvas trasparente
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

    # Quantizza l'alpha: semi-trasparenti -> opachi (255) se > 128, altrimenti 0.
    # Questo rimuove l'anti-aliasing del LANCZOS e dà pixel netti.
    alpha = final[..., 3]
    alpha_q = np.where(alpha > 128, 255, 0).astype(np.uint8)
    final[..., 3] = alpha_q

    # Applica palette 16 colori
    rgb_flat = final[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb_flat[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(SPRITE_SIZE, SPRITE_SIZE, 3)
    final = np.dstack([new_rgb, final[..., 3]]).astype(np.uint8)

    # Salva come sprite singolo 64x64
    out_path = SPRITES_DIR / f"{creature_id}_sheet.png"
    Image.fromarray(final, 'RGBA').save(out_path)

    # JSON: 1 colonna, 1 riga, 1 frame per animazione
    meta = {
        "image": f"{creature_id}_sheet.png",
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
    with open(SPRITES_DIR / f"{creature_id}_meta.json", "w") as f:
        json.dump(meta, f, indent=2)

    opachi = np.sum(final[..., 3] > 0)
    print(f"  [DONE] {creature_id}: 64x64, opachi={opachi}/{SPRITE_SIZE*SPRITE_SIZE}")
    return True

def main():
    # Supporta --only <id> per testare un singolo sprite
    only_id = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_id = sys.argv[2]

    print(f"=== Generazione sprite SINGOLI 64x64 pixel art ===")
    print(f"Totale: {len(CREATURES)} sprite")
    print(f"")

    success = 0
    for i, (cid, desc) in enumerate(CREATURES):
        if only_id and cid != only_id:
            continue
        # Salta se esiste gia'
        sheet_path = SPRITES_DIR / f"{cid}_sheet.png"
        if sheet_path.exists() and not only_id:
            print(f"[SKIP] {cid} (gia' esistente)")
            success += 1
            continue
        if i > 0 and not only_id:
            time.sleep(15)  # rate limit
        print(f"[GEN] {cid}")
        if process_sprite(cid, desc):
            success += 1
        else:
            # Retry una volta
            print(f"  retry con attesa 60s...")
            time.sleep(60)
            if process_sprite(cid, desc):
                success += 1

    print(f"")
    print(f"=== Done: {success}/{len(CREATURES) if not only_id else 1} ===")

if __name__ == "__main__":
    main()

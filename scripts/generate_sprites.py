#!/usr/bin/env python3
"""
generate_sprites.py - Genera gli spritesheet PNG per il bestiary fantasy horror.

Strategia (per minimizzare le chiamate API):
1. Per ogni creatura mappata, genera UN SOLO PNG a 1024x1024 che rappresenta
   uno spritesheet 6x4 (24 frame totali: 4 idle + 6 walk + 6 attack + 6 death
   con 2 frame vuoti alla fine della prima riga).
2. Ridimensiona il PNG a 384x256 (6 colonne x 4 righe x 64 px).
3. Ritaglia i 22 frame singoli.
4. Applica la palette 16 colori.
5. Salva lo spritesheet finale + i metadati JSON.

Mappatura creature (22 totali = 19 mostri + 3 boss):
  monster_001..020 (esclusi 014 Vampiro Minore che non e' nel gioco)
  boss_022, boss_029, boss_030

Output: /home/z/my-project/ArcadeMaze/assets/sprites/<id>_sheet.png
        + <id>_meta.json
"""
import os
import sys
import json
import subprocess
import tempfile
from pathlib import Path
from PIL import Image
import numpy as np

# --- Config ---
OUTPUT_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
TEMP_DIR = Path("/tmp/sprite_gen")
FRAME_W, FRAME_H = 64, 64
COLUMNS, ROWS = 6, 4
API_SIZE = "1024x1024"  # z-ai supporta solo queste dimensioni

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Creature da generare (22 totali: quelle mappate nel codice C++)
CREATURES = [
    ("monster_001", "Sghignazzante Ghoul",
     "rotten skeletal ghoul, long claws, ragged flesh, hunched posture"),
    ("monster_002", "Ragno Abissale",
     "abyssal spider, armored carapace, multiple glowing red eyes, dangling webs"),
    ("monster_003", "Lupo Spettrale",
     "spectral wolf, smoky fur, glowing green eyes, tattered collar"),
    ("monster_004", "Cultista Corrotto",
     "corrupted cultist, hooded robe, runic tattoos, ritual dagger"),
    ("monster_005", "Mimic Borsa",
     "mimic bag, mouth of teeth, leather straps, tongue flicking"),
    ("monster_006", "Ratto Gigante",
     "giant rat, matted fur, rotten teeth, scavenger posture"),
    ("monster_007", "Strega delle Paludi",
     "swamp witch, pointed hat, potion vials, greenish skin"),
    ("monster_008", "Scheletro Lanciere",
     "skeleton lancer, rusted armor, broken spear, hollow eyes"),
    ("monster_009", "Ombra Strisciante",
     "creeping shadow, amorphous form, smoky tendrils, no visible legs"),
    ("monster_010", "Golem di Ossa",
     "bone golem, massive ribcage, clanking joints, slow gait"),
    ("monster_011", "Serpente di Cenere",
     "ash serpent, smoky scales, ember eyes, sinuous body"),
    ("monster_012", "Cavaliere Dannato",
     "damned knight, blackened armor, ember cracks, tattered cape"),
    ("monster_013", "Mago Folle",
     "mad wizard, glowing eyes, torn robes, floating scrolls"),
    ("monster_015", "Corvo Demoniaco",
     "demonic crow, ragged wings, metallic beak, red eyes"),
    ("monster_016", "Tentacolo Sotterraneo",
     "subterranean tentacle, mucous skin, scattered eyes, writhing"),
    ("monster_017", "Gargoyle Vegliante",
     "watchful gargoyle, stone texture, broken wings, perched stance"),
    ("monster_018", "Spirito del Pozzo",
     "well spirit, watery face, bubble effects, translucent"),
    ("monster_019", "Cinghiale Maledetto",
     "cursed boar, mud-caked, tusks encrusted, low center of gravity"),
    ("monster_020", "Fungo Predatore",
     "predator fungus, glowing cap, spore puffs, stalky legs"),
    ("boss_022", "Regina Ragno Abissale",
     "queen spider, enormous abdomen, web banners, many eyes"),
    ("boss_029", "Vescovo Vampiro",
     "vampire bishop, ornate vestments, draining aura, teleport flicker"),
    ("boss_030", "Guardiano delle Profondita",
     "depths guardian, many tentacles, water shockwave, barnacle armor"),
]

ANIMATIONS = {
    "idle":   {"row": 0, "frames": 4, "duration": 200},
    "walk":   {"row": 1, "frames": 6, "duration": 100},
    "attack": {"row": 2, "frames": 6, "duration": 100},
    "death":  {"row": 3, "frames": 6, "duration": 120},
}

def build_prompt(desc, name):
    """Costruisce il prompt per generare uno spritesheet 6x4 a 1024x1024."""
    return (
        f"Pixel art spritesheet arranged in a 6 columns by 4 rows grid, "
        f"each cell is a 64x64 pixel frame, total image 384x256 scaled up. "
        f"16-color palette, fantasy horror, inspired by Dungeons & Dragons "
        f"and Ghosts'n Goblins. Transparent background (alpha). "
        f"Character: {desc}. "
        f"Row 1 (top): idle animation, 4 frames, character breathing. "
        f"Row 2: walk cycle, 6 frames, side view movement. "
        f"Row 3: attack animation, 6 frames, striking pose. "
        f"Row 4: death animation, 6 frames, falling and dissolving. "
        f"Mood: menacing, gothic lighting, high contrast shading, crisp outlines. "
        f"Anchor feet at y=56 of each 64x64 frame. "
        f"Consistent character proportions across all frames. "
        f"No text, no UI, no watermark, no grid lines."
    )

def generate_image_zai(prompt, output_path):
    """Chiama z-ai CLI per generare un'immagine 1024x1024."""
    cmd = ["z-ai", "image", "-p", prompt, "-o", str(output_path), "-s", API_SIZE]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"  ERROR z-ai: {result.stderr[:300]}")
        return False
    return output_path.exists()

def process_spritesheet(raw_png_path, creature_id):
    """
    Processa il PNG grezzo 1024x1024:
    1. Ridimensiona a 384x256 (6x4 frame a 64px).
    2. Applica palette 16 colori mantenendo alpha.
    3. Salva come <creature_id>_sheet.png.
    4. Genera il metadata JSON.
    """
    img = Image.open(raw_png_path).convert("RGBA")
    # Ridimensiona a 384x256 con NEAREST per mantenere i pixel netti
    target_w = COLUMNS * FRAME_W  # 384
    target_h = ROWS * FRAME_H     # 256
    img = img.resize((target_w, target_h), resample=Image.NEAREST)

    # Applica palette 16 colori
    arr = np.array(img)
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    # Distanza quadrata ai colori della palette
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    new_img = np.dstack([new_rgb, arr[..., 3]])
    out = Image.fromarray(new_img.astype('uint8'), 'RGBA')

    # Salva lo spritesheet
    sheet_path = OUTPUT_DIR / f"{creature_id}_sheet.png"
    out.save(sheet_path)
    print(f"  Salvato {sheet_path.name} ({out.size[0]}x{out.size[1]})")

    # Salva il metadata JSON
    meta = {
        "image": f"{creature_id}_sheet.png",
        "frameWidth": FRAME_W,
        "frameHeight": FRAME_H,
        "columns": COLUMNS,
        "rows": ROWS,
        "anchor": {"x": 32, "y": 56},
        "animations": {k: {"row": v["row"], "frames": v["frames"],
                          "frameDuration": v["duration"]}
                       for k, v in ANIMATIONS.items()}
    }
    meta_path = OUTPUT_DIR / f"{creature_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    return sheet_path

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)

    # Modalita': se si passa "--only <id>" genera solo quella creatura
    only_id = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_id = sys.argv[2]

    success = 0
    failed = []
    for cid, name, desc in CREATURES:
        if only_id and cid != only_id:
            continue
        sheet_path = OUTPUT_DIR / f"{cid}_sheet.png"
        if sheet_path.exists():
            print(f"[SKIP] {cid} ({name}) - spritesheet gia' esistente")
            success += 1
            continue
        print(f"[GEN]  {cid} ({name})...")
        prompt = build_prompt(desc, name)
        raw_path = TEMP_DIR / f"{cid}_raw.png"
        if not generate_image_zai(prompt, raw_path):
            failed.append(cid)
            continue
        process_spritesheet(raw_path, cid)
        success += 1

    print(f"\n=== Riepilogo ===")
    print(f"Generati con successo: {success}/{len(CREATURES) if not only_id else 1}")
    if failed:
        print(f"Falliti: {', '.join(failed)}")
    return 0 if not failed else 1

if __name__ == "__main__":
    sys.exit(main())

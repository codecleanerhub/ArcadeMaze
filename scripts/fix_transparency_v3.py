#!/usr/bin/env python3
"""
fix_transparency_v3.py - Crea sprite statici singoli 64x64 dai raw AI.

PROBLEMA: l'AI generatore (z-ai) NON genera spritesheet strutturati 6x4
come richiesto dal prompt. Genera invece una singola immagine del personaggio.
Quando il codice C++ divide questa immagine in 24 frame, ottiene 24 ritagli
della stessa immagine -> effetto "gif animata che scorre".

SOLUZIONE: usare il raw 1024x1024 come sprite SINGOLO 64x64:
1. Carica il raw 1024x1024
2. Ritaglia un quadrato centrale (dove c'è il personaggio)
3. Flood-fill transparency dal bordo
4. Ridimensiona a 64x64 con NEAREST
5. Applica palette 16 colori
6. Salva come <id>_sheet.png (64x64, NON 384x256)
7. Aggiorna il JSON: columns=1, rows=1, tutte le animazioni hanno 1 frame

Il codice C++ SpriteSheet gestisce già questo caso: con columns=1, rows=1,
frameW=64, frameH=64, ogni animazione ha 1 frame. Il render disegna sempre
quel singolo frame. Per dare un po' di vita, il codice C++ puo' applicare
un offset verticale (bob effect) per simulare camminata/respirazione.
"""
import os
import json
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque

RAW_DIR = Path("/tmp/sprite_gen")
SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")

# Dimensioni sprite finale
SPRITE_SIZE = 64  # 64x64 pixel

# Ritaglio centrale dal raw 1024x1024 (il personaggio di solito e' al centro)
# Usiamo un quadrato di 768x768 centrato, per evitare bordi con artefatti
CROP_SIZE = 768

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Tolleranza per flood-fill
TOL = 25

def flood_fill_transparency(arr):
    """Rende trasparenti i pixel di sfondo connessi al bordo via flood-fill."""
    h, w = arr.shape[:2]
    rgb = arr[..., :3].astype(int)

    # Colori dei 4 angoli come riferimenti di sfondo
    corners = [rgb[0,0], rgb[0,-1], rgb[-1,0], rgb[-1,-1]]
    dist_to_corners = np.stack([
        np.sum((rgb - c) ** 2, axis=2) for c in corners
    ], axis=0)
    min_dist = dist_to_corners.min(axis=0)
    is_bg_candidate = min_dist < TOL**2

    # Flood fill dal bordo
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h-1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w-1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_candidate[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    alpha = arr[..., 3]
    alpha[visited] = 0
    return visited.sum()

def apply_palette(arr):
    """Applica la palette 16 colori mantenendo alpha."""
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    return np.dstack([new_rgb, arr[..., 3]])

def process_creature(creature_id):
    """Processa un raw 1024x1024 -> sprite statico 64x64."""
    raw_path = RAW_DIR / f"{creature_id}_raw.png"
    if not raw_path.exists():
        print(f"  [SKIP] {creature_id}: raw non trovato")
        return False

    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]

    # 1) Ritaglia il quadrato centrale CROP_SIZE x CROP_SIZE
    cy, cx = h // 2, w // 2
    half = CROP_SIZE // 2
    y0 = max(0, cy - half)
    y1 = min(h, cy + half)
    x0 = max(0, cx - half)
    x1 = min(w, cx + half)
    arr = arr[y0:y1, x0:x1]

    # 2) Flood-fill transparency
    bg_count = flood_fill_transparency(arr)

    # 3) Ridimensiona a 64x64 con NEAREST (mantiene pixel art netti)
    img = Image.fromarray(arr, 'RGBA')
    img = img.resize((SPRITE_SIZE, SPRITE_SIZE), resample=Image.NEAREST)
    arr = np.array(img)

    # 4) Applica palette 16 colori
    arr = apply_palette(arr)

    # 5) Salva come sprite 64x64 singolo
    out = Image.fromarray(arr.astype('uint8'), 'RGBA')
    out_path = SPRITES_DIR / f"{creature_id}_sheet.png"
    out.save(out_path)

    # 6) Aggiorna il JSON: columns=1, rows=1, 1 frame per ogni animazione
    meta = {
        "image": f"{creature_id}_sheet.png",
        "frameWidth": SPRITE_SIZE,
        "frameHeight": SPRITE_SIZE,
        "columns": 1,
        "rows": 1,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": 1, "frameDuration": 200},
            "walk":   {"row": 0, "frames": 1, "frameDuration": 100},
            "attack": {"row": 0, "frames": 1, "frameDuration": 100},
            "death":  {"row": 0, "frames": 1, "frameDuration": 120}
        }
    }
    meta_path = SPRITES_DIR / f"{creature_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    transparent = np.sum(arr[..., 3] == 0)
    total = arr.shape[0] * arr.shape[1]
    print(f"  [OK] {creature_id}: 64x64, trasparenti={transparent}/{total} ({transparent/total*100:.1f}%)")
    return True

# Tutte le creature
CREATURES = [
    "monster_001","monster_002","monster_003","monster_004","monster_005",
    "monster_006","monster_007","monster_008","monster_009","monster_010",
    "monster_011","monster_012","monster_013","monster_015","monster_016",
    "monster_017","monster_018","monster_019","monster_020",
    "boss_021","boss_022","boss_023","boss_024","boss_025","boss_026",
    "boss_027","boss_028","boss_029","boss_030",
    "player1","player2"
]

def main():
    print(f"Processo {len(CREATURES)} sprite -> sprite statici 64x64 singoli")
    print(f"")
    ok = 0
    for cid in CREATURES:
        if process_creature(cid):
            ok += 1
    print(f"")
    print(f"Done: {ok}/{len(CREATURES)} sprite processati.")
    print(f"")
    print(f"NOTA: ogni sprite ora e' 64x64 (non piu' 384x256).")
    print(f"Il codice C++ carichera' 1 frame singolo per ogni animazione.")
    print(f"Nessun effetto 'gif animata che scorre'.")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
fix_transparency_v2.py - Post-processa gli sprite PNG con flood-fill dal bordo.

L'AI generatore (z-ai) genera PNG con sfondo scuro opaco (alpha=255 ovunque).
Questo script usa un approccio flood-fill:
1. Parte dai pixel del bordo (cornice del PNG)
2. Rende trasparenti tutti i pixel "vicini al colore di sfondo" che sono
   connessi (direttamente o attraverso altri pixel di sfondo) al bordo.
3. Le parti interne del personaggio (anche se scure) vengono preservate
   perche' non sono connesse al bordo.

Rispetto alla v1 (color keying globale), questo preserva i dettagli scuri
del personaggio (orbite, ombre, ecc.).

Prerequisiti: i raw originali 1024x1024 devono essere in /tmp/sprite_gen/.
Output: sovrascrive i <id>_sheet.png in assets/sprites/ con la versione
ridimensionata + palette 16 colori + trasparenza flood-fill.
"""
import os
import sys
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque

RAW_DIR = Path("/tmp/sprite_gen")
SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
FRAME_W, FRAME_H = 64, 64
COLUMNS, ROWS = 6, 4

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Tolleranza per flood-fill: pixel con distanza quadrata < TOL^2 dal
# colore di uno dei 4 angoli vengono considerati "sfondo".
# TOL=25 e' calibrato per preservare i dettagli del personaggio che hanno
# colori simili allo sfondo (es. verde scuro del personaggio vs nero sfondo).
TOL = 25

def flood_fill_transparency(arr):
    """
    Rende trasparenti tutti i pixel di sfondo connessi al bordo.
    Usa una tolleranza per-pixel: ogni pixel del bordo avvia il flood-fill
    con il proprio colore come riferimento locale. Questo gestisce sfondi
    non uniformi (es. gradiente o sfondo bicolore).

    arr: array HxWx4 (RGBA), modificato in-place.
    """
    h, w = arr.shape[:2]
    rgb = arr[..., :3].astype(int)

    # Tolleranza: pixel con distanza quadrata < TOL^2 dal colore di riferimento
    # vengono considerati "sfondo".
    # Strategia: flood-fill multipli, uno per ogni pixel del bordo, usando
    # il colore del pixel di partenza come riferimento locale.

    visited = np.zeros((h, w), dtype=bool)
    is_bg = np.zeros((h, w), dtype=bool)  # marcatore finale "e' sfondo"

    queue = deque()
    # Raccogliamo tutti i pixel del bordo come seed
    seeds = []
    for x in range(w):
        seeds.append((0, x)); seeds.append((h-1, x))
    for y in range(h):
        seeds.append((y, 0)); seeds.append((y, w-1))

    # Per ogni seed, avvia BFS con tolleranza rispetto al colore del seed.
    # Usiamo una variante: invece di fare BFS separati, facciamo un'unica
    # BFS dove ogni pixel viene confrontato col colore del seed originale.
    # Pero' e' piu' efficiente fare cosi: se un pixel e' vicino (TOL) a
    # ALMENO UNO dei colori dei 4 angoli, e' candidato sfondo.
    corners = [rgb[0,0], rgb[0,-1], rgb[-1,0], rgb[-1,-1]]
    dist_to_corners = np.stack([
        np.sum((rgb - c) ** 2, axis=2) for c in corners
    ], axis=0)
    min_dist = dist_to_corners.min(axis=0)
    is_bg_candidate = min_dist < TOL**2

    # Flood fill dai pixel del bordo che sono candidati sfondo
    for y, x in seeds:
        if is_bg_candidate[y, x] and not visited[y, x]:
            visited[y, x] = True
            queue.append((y, x))

    # BFS 4-connesso: propaga solo attraverso pixel candidati sfondo
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_candidate[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    # I pixel visitati (connessi al bordo) sono sfondo -> trasparenti
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
    """Processa un raw 1024x1024 -> spritesheet 384x256 con trasparenza."""
    raw_path = RAW_DIR / f"{creature_id}_raw.png"
    if not raw_path.exists():
        print(f"  [SKIP] {creature_id}: raw non trovato")
        return False

    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)

    # 1) Flood-fill transparency SUL RAW 1024x1024 (prima del resize)
    bg_count = flood_fill_transparency(arr)

    # 2) Resize a 384x256 con NEAREST
    img = Image.fromarray(arr, 'RGBA')
    img = img.resize((COLUMNS*FRAME_W, ROWS*FRAME_H), resample=Image.NEAREST)
    arr = np.array(img)

    # 3) Applica palette 16 colori
    arr = apply_palette(arr)

    # 4) Salva
    out = Image.fromarray(arr.astype('uint8'), 'RGBA')
    out_path = SPRITES_DIR / f"{creature_id}_sheet.png"
    out.save(out_path)

    total = arr.shape[0] * arr.shape[1]
    transparent = np.sum(arr[..., 3] == 0)
    pct = transparent / total * 100
    print(f"  [OK] {creature_id}: sfondo={bg_count}px, trasparenti={transparent}/{total} ({pct:.1f}%)")
    return True

# Tutte le creature da processare
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
    print(f"Processo {len(CREATURES)} sprite con flood-fill transparency")
    print(f"")
    ok = 0
    for cid in CREATURES:
        if process_creature(cid):
            ok += 1
    print(f"")
    print(f"Done: {ok}/{len(CREATURES)} sprite processati.")

if __name__ == "__main__":
    main()

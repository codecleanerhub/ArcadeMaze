#!/usr/bin/env python3
"""
regen_boss_sprites.py - Rigenera gli sprite 64x64 di boss_035 (Ancient Dragon)
e boss_021 (Ghoul Lord) dai raw AI 1024x1024.

PROBLEMA RISOLTO:
- boss_035 (Ancient Dragon): 78% trasparenza totale, meta' bassa 89.9% vuota.
  Il corpo del drago mancava quasi del tutto nella zona inferiore.
- boss_021 (Ghoul Lord): 58.9% trasparenza, sparse zone vuote.

PIPELINE:
1. Carica il raw 1024x1024.
2. Flood-fill transparency dal bordo (rimuove il nero di sfondo uniforme).
3. Trova il bounding box dei pixel non-trasparenti (il personaggio).
4. Ritaglia al bounding box + margine.
5. Ridimensiona a 64x64 con LANCZOS (qualita' alta, mantiene anti-aliasing).
6. CHIAVE: "riempi i buchi" intra-corpo - identifica i pixel trasparenti
   che sono CIRCONDATI da pixel opachi (buchi nel corpo) e riempili con
   il colore del vicino piu' vicino. Questo elimina i gap di trasparenza
   nella silhouette del personaggio.
7. Per il dragon: rinforza il rosso nella meta' bassa - se un pixel
   trasparente intra-corpo si trova nella meta' inferiore, riempilo con
   rosso scuro (palette boss_035).
8. Applica palette 16 colori.
9. Salva <id>_sheet.png (64x64 singolo frame) + aggiorna meta.json.

Il risultato e' uno sprite SOLIDO senza buchi di trasparenza nel corpo,
mantenendo solo la trasparenza esterna (lo sfondo attorno al personaggio).
"""
import os
import json
import sys
from pathlib import Path
from PIL import Image
import numpy as np
from collections import deque

# --- Config ---
RAW_DIR = Path("/tmp/sprite_gen")
SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
SPRITE_SIZE = 64
CROP_MARGIN = 12  # margine attorno al bounding box del personaggio (in pixel a 1024)

# Palette 16 colori (stessa di generate_sprites.py per coerenza visiva)
PALETTE = [
    (12, 12, 12),   (48, 40, 36),   (96, 80, 72),   (160, 128, 112),
    (200, 180, 160), (120, 140, 160), (80, 120, 100),  (40, 80, 60),
    (160, 40, 40),  (200, 80, 80),  (220, 160, 40),  (200, 200, 80),
    (120, 200, 200), (80, 160, 220), (160, 120, 200), (240, 240, 240)
]

# Tolleranza per flood-fill del colore di sfondo
TOL = 28


def flood_fill_transparency(arr):
    """
    Marca come trasparenti tutti i pixel di sfondo connessi al bordo.
    Lo sfondo e' identificato dai colori dei 4 angoli (con tolleranza).
    Restituisce una maschera booleana (True = pixel di sfondo da rimuovere).
    """
    h, w = arr.shape[:2]
    rgb = arr[..., :3].astype(int)

    # Colori dei 4 angoli come riferimenti di sfondo
    corners = [rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]]
    dist_to_corners = np.stack([
        np.sum((rgb - c) ** 2, axis=2) for c in corners
    ], axis=0)
    min_dist = dist_to_corners.min(axis=0)
    is_bg_candidate = min_dist < TOL ** 2

    # Flood fill dal bordo (BFS)
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w - 1]:
            if is_bg_candidate[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_candidate[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    return visited


def find_bounding_box(alpha):
    """Trova il bounding box dei pixel non-trasparenti. Restituisce (y0, y1, x0, x1)."""
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not rows.any() or not cols.any():
        return None
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    return int(rmin), int(rmax), int(cmin), int(cmax)


def fill_internal_holes(rgba):
    """
    RIEMPIE I BUCHI INTRA-CORPO.

    Identifica i pixel trasparenti che sono CIRCONDATI da pixel opachi
    (buchi nella silhouette del personaggio) e li riempie con il colore
    del pixel opaco piu' vicino.

    Algoritmo:
    1. Flood-fill dal bordo esterno: marca tutti i pixel trasparenti connessi
       al bordo (questi sono lo sfondo esterno - corretti).
    2. I pixel trasparenti NON raggiungibili dal bordo sono "buchi" intra-corpo
       e vengono riempiti con la media dei pixel opachi in un intorno crescente.
    """
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3]

    # Maschera dei pixel trasparenti
    transparent_mask = (alpha == 0)

    # Flood-fill dal bordo esterno (8-connessione)
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if transparent_mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in [0, w - 1]:
            if transparent_mask[y, x] and not visited[y, x]:
                visited[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and transparent_mask[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    # I pixel trasparenti NON visitati sono "buchi intra-corpo"
    holes = transparent_mask & (~visited)
    n_holes = int(holes.sum())
    print(f"    Buchi intra-corpo trovati: {n_holes}")

    if n_holes == 0:
        return rgba

    # Riempi ogni buco con il colore medio dei pixel opachi in un intorno crescente
    rgb = rgba[..., :3].astype(int).copy()
    filled_alpha = alpha.copy()

    ys, xs = np.where(holes)
    for y, x in zip(ys, xs):
        # Cerca pixel opachi in un raggio crescente
        found = False
        for r in range(1, 12):
            y0 = max(0, y - r); y1 = min(h, y + r + 1)
            x0 = max(0, x - r); x1 = min(w, x + r + 1)
            neighborhood_alpha = alpha[y0:y1, x0:x1]
            neighborhood_rgb = rgb[y0:y1, x0:x1]
            mask = neighborhood_alpha > 0
            if mask.sum() > 0:
                rgb[y, x] = neighborhood_rgb[mask].mean(axis=0).astype(int)
                filled_alpha[y, x] = 255
                found = True
                break
        # Se non trovato in raggio 11, lascia trasparente

    rgba_new = np.dstack([rgb, filled_alpha]).astype(np.uint8)
    return rgba_new


def reinforce_red_lower_half(rgba, threshold_y_frac=0.45):
    """
    Per il dragon (boss_035): rinforza il ROSSO nella meta' bassa dello sprite.

    Dopo il fill dei buchi, alcuni pixel potrebbero essere stati riempiti
    con colori troppo neutri. Per garantire che la zona inferiore del drago
    sia inequivocabilmente ROSSA:

    1. Identifica i pixel nella meta' bassa (y > threshold_y_frac * h).
    2. Per i pixel "grigiastri" scuri (R~G~B, luminanza <90), spostali
       verso un rosso scuro.
    3. Per i pixel troppo chiari e neutri (luminanza >180, R<150), applica
       una tinta rosso.

    Non tocca i pixel gia' rossi ne' i highlight chiari rossi.
    """
    h, w = rgba.shape[:2]
    threshold_y = int(h * threshold_y_frac)
    rgb = rgba[..., :3].astype(int).copy()

    for y in range(threshold_y, h):
        for x in range(w):
            r, g, b = rgb[y, x]
            is_reddish = (r > g + 10) and (r > b + 10)
            luminance = (r + g + b) // 3
            is_dark_shadow = (luminance < 90) and (abs(r - g) < 30) and (abs(r - b) < 30)
            is_too_bright = (luminance > 180) and (r < 150)

            if is_dark_shadow:
                new_r = int(r * 0.4 + 100 * 0.6)
                new_g = int(g * 0.4 + 20 * 0.6)
                new_b = int(b * 0.4 + 20 * 0.6)
                rgb[y, x] = (new_r, new_g, new_b)
            elif is_too_bright and not is_reddish:
                new_r = int(r * 0.5 + 200 * 0.5)
                new_g = int(g * 0.5 + 80 * 0.5)
                new_b = int(b * 0.5 + 80 * 0.5)
                rgb[y, x] = (new_r, new_g, new_b)

    rgba_new = np.dstack([rgb, rgba[..., 3]]).astype(np.uint8)
    return rgba_new


def apply_palette(rgba):
    """Applica palette 16 colori mantenendo alpha. Ritorna uint8 RGBA."""
    arr = rgba
    alpha = arr[..., 3]
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    rgb[alpha.reshape(-1) == 0] = [0, 0, 0]

    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    result = np.dstack([new_rgb, alpha]).astype(np.uint8)
    return result


def process_creature(creature_id, reinforce_red=False):
    """Pipeline completa: raw 1024x1024 -> sprite 64x64 solido."""
    raw_path = RAW_DIR / f"{creature_id}_raw_new.png"
    if not raw_path.exists():
        print(f"  [SKIP] {creature_id}: raw non trovato a {raw_path}")
        return False

    print(f"\n[GEN] {creature_id}: lettura raw 1024x1024...")
    img = Image.open(raw_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    print(f"    Dimensioni raw: {w}x{h}")

    # 1) Flood-fill transparency dal bordo
    print(f"    1) Flood-fill transparency...")
    bg_mask = flood_fill_transparency(arr)
    arr[bg_mask, 3] = 0
    n_bg = int(bg_mask.sum())
    print(f"       Pixel di sfondo rimossi: {n_bg} ({n_bg/(h*w)*100:.1f}%)")

    # 2) Trova il bounding box
    print(f"    2) Trova bounding box del personaggio...")
    bbox = find_bounding_box(arr[..., 3])
    if bbox is None:
        print(f"    [ERROR] Nessun pixel non-trasparente trovato!")
        return False
    rmin, rmax, cmin, cmax = bbox
    print(f"       BBox: y={rmin}..{rmax} (h={rmax-rmin+1}), x={cmin}..{cmax} (w={cmax-cmin+1})")

    # 3) Ritaglia al bounding box + margine
    y0 = max(0, rmin - CROP_MARGIN)
    y1 = min(h, rmax + CROP_MARGIN + 1)
    x0 = max(0, cmin - CROP_MARGIN)
    x1 = min(w, cmax + CROP_MARGIN + 1)
    arr = arr[y0:y1, x0:x1]
    print(f"       Crop (con margine {CROP_MARGIN}px): {arr.shape[1]}x{arr.shape[0]}")

    # 4) Fill dei buchi intra-corpo
    print(f"    3) Fill dei buchi intra-corpo...")
    arr = fill_internal_holes(arr)

    # 5) Rinforzo rosso nella meta' bassa (solo dragon)
    if reinforce_red:
        print(f"    4) Rinforzo rosso nella meta' bassa...")
        arr = reinforce_red_lower_half(arr, threshold_y_frac=0.45)

    # 6) Resize a 64x64 con LANCZOS
    print(f"    5) Resize a {SPRITE_SIZE}x{SPRITE_SIZE} con LANCZOS...")
    img = Image.fromarray(arr, 'RGBA')
    img = img.resize((SPRITE_SIZE, SPRITE_SIZE), resample=Image.LANCZOS)
    arr = np.array(img)

    # 7) Soglia alpha (anti-aliasing) -> 0/255 netto
    alpha = arr[..., 3]
    arr[alpha < 32, 3] = 0
    arr[alpha >= 32, 3] = 255

    # 8) Post-fill micro-buchi creati dal resize
    print(f"    6) Post-fill micro-buchi post-resize...")
    arr = fill_internal_holes(arr)

    # 9) Applica palette
    print(f"    7) Applica palette 16 colori...")
    arr = apply_palette(arr)

    # Salva
    out = Image.fromarray(arr.astype('uint8'), 'RGBA')
    out_path = SPRITES_DIR / f"{creature_id}_sheet.png"
    out.save(out_path)

    # Statistiche
    transparent = int(np.sum(arr[..., 3] == 0))
    total = arr.shape[0] * arr.shape[1]
    low_transparent = int(np.sum(arr[32:, 3] == 0))
    low_total = arr.shape[1] * 32
    high_transparent = int(np.sum(arr[:32, 3] == 0))
    high_total = arr.shape[1] * 32
    print(f"    [OK] Salvato {out_path.name}")
    print(f"       Trasparenza totale: {transparent}/{total} = {transparent/total*100:.1f}%")
    print(f"       Meta' alta  (y<32):  {high_transparent}/{high_total} = {high_transparent/high_total*100:.1f}%")
    print(f"       Meta' bassa (y>=32): {low_transparent}/{low_total} = {low_transparent/low_total*100:.1f}%")

    # Top 5 colori
    mask = arr[..., 3] > 0
    if mask.sum() > 0:
        rgb = arr[..., :3][mask]
        q = (rgb // 32) * 32
        cols, cnts = np.unique(q, axis=0, return_counts=True)
        idx = np.argsort(-cnts)[:5]
        print(f"       Top 5 colori:")
        for i in idx:
            print(f"         RGB~{tuple(int(x) for x in cols[i])}: {cnts[i]} pixel")

    # 10) Aggiorna meta.json
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
    print(f"    [OK] Meta JSON aggiornato: {meta_path.name}")

    return True


def main():
    SPRITES_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("REGEN BOSS SPRITES - boss_035 + boss_021")
    print("=" * 60)

    ok1 = process_creature("boss_035", reinforce_red=True)
    ok2 = process_creature("boss_021", reinforce_red=False)

    print("\n" + "=" * 60)
    print(f"Riepilogo:")
    print(f"  boss_035 (Ancient Dragon): {'OK' if ok1 else 'FAIL'}")
    print(f"  boss_021 (Ghoul Lord):     {'OK' if ok2 else 'FAIL'}")
    print("=" * 60)
    return 0 if (ok1 and ok2) else 1


if __name__ == "__main__":
    sys.exit(main())

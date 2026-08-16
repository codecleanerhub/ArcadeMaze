#!/usr/bin/env python3
"""
fix_sprites_v4.py - Crea spritesheet 3x4 corretti dai raw AI.

SCOPERTA: l'AI genera spritesheet 3x4 (3 colonne x 4 righe = 12 frame)
con celle 341x256 px su sfondo uniforme (bianco o nero).

FIX PRECEDENTI FALLITI:
- v1/v2: flood-fill su 1024x1024 poi resize 384x256 NEAREST -> distruggeva
- v3: resize 1024->64 NEAREST -> noise casuale (1 pixel ogni 16)

STRATEGIA CORRETTA (v4):
1. Per ogni raw 1024x1024, dividi in griglia 3x4 (12 celle 341x256)
2. Per ogni cella:
   a. Color keying: rimuovi il colore di sfondo (rilevato dagli angoli)
      con tolleranza, usando alpha sfumato per anti-aliasing
   b. Ritaglia al bounding box del personaggio (rimuovi bordi vuoti)
   c. Ridimensiona a 64x64 con LANCZOS (qualità alta, non NEAREST)
3. Assembla le 12 celle 64x64 in uno spritesheet 192x256 (3x6... no,
   3 colonne x 4 righe = 192x256)
4. Applica palette 16 colori
5. Salva <id>_sheet.png + JSON con columns=3, rows=4

Il codice C++ SpriteSheet carica correttamente: columns=3, rows=4,
frameW=64, frameH=64. Ogni animazione ha 3 frame (una riga).
Mappatura: idle=row0, walk=row1, attack=row2, death=row3.
"""
import os
import json
from pathlib import Path
from PIL import Image
import numpy as np

RAW_DIR = Path("/tmp/sprite_gen")
SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")

# Formato spritesheet
COLS, ROWS = 3, 4
FRAME_SIZE = 64  # ogni frame ridimensionato a 64x64

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

# Tolleranza per color keying dello sfondo
BG_TOL = 30

def remove_background(cell_arr):
    """
    Rimuovi lo sfondo da una cella usando color keying.
    Lo sfondo è il colore piu' frequente tra i pixel del bordo superiore.
    Usa alpha sfumato per anti-aliasing ai bordi.
    """
    h, w = cell_arr.shape[:2]
    rgb = cell_arr[..., :3].astype(int)

    # Colore sfondo: il piu' frequente tra i pixel della prima riga.
    # Usiamo la media dei 10 pixel piu' chiari o piu' scuri (a seconda di
    # quale gruppo è piu' numeroso), per robustezza.
    top_row = rgb[0, :, :]  # prima riga: w pixel
    # Quantizza a 16 livelli per canale per trovare il colore dominante
    quantized = (top_row // 16) * 16
    # Trova il colore piu' frequente
    colors, counts = np.unique(quantized, axis=0, return_counts=True)
    bg_q = colors[np.argmax(counts)]
    # Media dei pixel originali che corrispondono al colore dominante quantizzato
    mask = np.all(np.abs(quantized - bg_q) <= 8, axis=1)
    if mask.sum() > 0:
        bg = np.mean(top_row[mask], axis=0).astype(int)
    else:
        bg = np.median(top_row, axis=0).astype(int)

    # Distanza dal colore di sfondo
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))

    # Alpha: 0 se vicino allo sfondo, 255 se lontano, sfumato in mezzo
    alpha = np.clip((dist - BG_TOL) / BG_TOL, 0, 1) * 255
    alpha = alpha.astype(np.uint8)

    # Crea RGBA
    rgba = np.dstack([cell_arr[..., :3], alpha])
    return rgba, bg

def crop_to_content(rgba):
    """
    Ritaglia al bounding box dei pixel non trasparenti.
    Rimuove i bordi vuoti per centrare meglio il personaggio.
    """
    alpha = rgba[..., 3]
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not rows.any() or not cols.any():
        return rgba
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    # Aggiungi margine di 2 pixel
    rmin = max(0, rmin - 2)
    rmax = min(rgba.shape[0], rmax + 3)
    cmin = max(0, cmin - 2)
    cmax = min(rgba.shape[1], cmax + 3)
    return rgba[rmin:rmax, cmin:cmax]

def resize_frame(rgba, size=FRAME_SIZE):
    """
    Ridimensiona a size x size con LANCZOS (qualità alta).
    Mantiene l'aspect ratio centrando su sfondo trasparente.
    """
    h, w = rgba.shape[:2]
    if h == 0 or w == 0:
        return np.zeros((size, size, 4), dtype=np.uint8)

    img = Image.fromarray(rgba, 'RGBA')

    # Scala mantenendo aspect ratio
    scale = min(size / w, size / h)
    new_w = max(1, int(w * scale))
    new_h = max(1, int(h * scale))
    img = img.resize((new_w, new_h), resample=Image.LANCZOS)

    # Centra su canvas size x size trasparente
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    offset = ((size - new_w) // 2, (size - new_h) // 2)
    canvas.paste(img, offset, img)
    return np.array(canvas)

def apply_palette(rgba):
    """Applica palette 16 colori mantenendo alpha. Ritorna uint8 RGBA."""
    arr = rgba
    rgb = arr[..., :3].reshape(-1, 3).astype(int)
    alpha = arr[..., 3]
    palette_arr = np.array(PALETTE)
    dists = np.sum((rgb[:, None, :] - palette_arr[None, :, :]) ** 2, axis=2)
    idxs = np.argmin(dists, axis=1)
    new_rgb = palette_arr[idxs].reshape(arr.shape[0], arr.shape[1], 3)
    # Combina e assicurati che sia uint8 (altrimenti Image.fromarray fallisce)
    result = np.dstack([new_rgb, alpha]).astype(np.uint8)
    return result

def process_creature(creature_id):
    """Processa un raw 1024x1024 -> spritesheet 3x4 a 64x64 per frame."""
    raw_path = RAW_DIR / f"{creature_id}_raw.png"
    if not raw_path.exists():
        print(f"  [SKIP] {creature_id}: raw non trovato")
        return False

    raw = Image.open(raw_path).convert('RGB')
    arr = np.array(raw)
    h, w = arr.shape[:2]

    # Dimensioni cella nella griglia 3x4
    cw = w // COLS  # 341
    ch = h // ROWS  # 256

    # Crea spritesheet finale 192x256 (3*64 x 4*64)
    sheet = np.zeros((ROWS * FRAME_SIZE, COLS * FRAME_SIZE, 4), dtype=np.uint8)

    bg_colors = []
    for r in range(ROWS):
        for c in range(COLS):
            # Estrai cella
            cell = arr[r*ch:(r+1)*ch, c*cw:(c+1)*cw]
            # Rimuovi sfondo
            rgba, bg = remove_background(cell)
            bg_colors.append(bg)
            # Ritaglia al contenuto
            rgba = crop_to_content(rgba)
            # Ridimensiona a 64x64
            frame = resize_frame(rgba)
            # Posiziona nello sheet
            sheet[r*FRAME_SIZE:(r+1)*FRAME_SIZE,
                  c*FRAME_SIZE:(c+1)*FRAME_SIZE] = frame

    # Applica palette 16 colori
    sheet = apply_palette(sheet)

    # Salva
    out = Image.fromarray(sheet, 'RGBA')
    out_path = SPRITES_DIR / f"{creature_id}_sheet.png"
    out.save(out_path)

    # JSON: 3 colonne, 4 righe, 3 frame per animazione (una riga)
    meta = {
        "image": f"{creature_id}_sheet.png",
        "frameWidth": FRAME_SIZE,
        "frameHeight": FRAME_SIZE,
        "columns": COLS,
        "rows": ROWS,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": COLS, "frameDuration": 200},
            "walk":   {"row": 1, "frames": COLS, "frameDuration": 100},
            "attack": {"row": 2, "frames": COLS, "frameDuration": 100},
            "death":  {"row": 3, "frames": COLS, "frameDuration": 120}
        }
    }
    meta_path = SPRITES_DIR / f"{creature_id}_meta.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    # Statistiche
    transparent = np.sum(sheet[..., 3] == 0)
    total = sheet.shape[0] * sheet.shape[1]
    bg_avg = np.mean(bg_colors, axis=0).astype(int)
    print(f"  [OK] {creature_id}: 3x4 grid, sfondo={tuple(bg_avg)}, trasparenti={transparent}/{total} ({transparent/total*100:.1f}%)")
    return True

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
    print(f"Processo {len(CREATURES)} sprite -> spritesheet 3x4 a 64x64/frame")
    print(f"")
    ok = 0
    for cid in CREATURES:
        if process_creature(cid):
            ok += 1
    print(f"")
    print(f"Done: {ok}/{len(CREATURES)} sprite processati.")

if __name__ == "__main__":
    main()

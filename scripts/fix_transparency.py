#!/usr/bin/env python3
"""
fix_transparency.py - Post-processa gli sprite PNG per rendere trasparente lo sfondo.

L'AI generatore (z-ai) NON rispetta il prompt "transparent background" e genera
PNG con sfondo scuro opaco (alpha=255 ovunque). Questo script:
1. Rileva il colore di sfondo dal pixel (0,0) di ogni spritesheet
2. Rende trasparenti (alpha=0) tutti i pixel entro una tolleranza da quel colore
3. Salva il PNG sovrascrivendo l'originale

Strategia: color keying con tolleranza. Il colore di sfondo di solito e'
quasi nero (RGB 0-15).
"""
import os
import sys
from pathlib import Path
from PIL import Image
import numpy as np

SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
TOLERANCE = 30  # Distanza quadrata massima dal colore di sfondo

def process_sprite(png_path):
    """Rende trasparente lo sfondo di un PNG usando color keying."""
    img = Image.open(png_path).convert("RGBA")
    arr = np.array(img)

    # Rileva colore di sfondo dal pixel (0,0)
    bg_color = arr[0, 0, :3].astype(int)
    # Calcola distanza quadrata di ogni pixel dal colore di sfondo
    rgb = arr[..., :3].astype(int)
    dist_sq = np.sum((rgb - bg_color) ** 2, axis=2)

    # Crea maschera: pixel vicini allo sfondo -> trasparenti
    # Usa una transizione morbida: alpha scalato in base alla distanza
    # entro una banda di tolleranza per evitare aliasing.
    alpha = arr[..., 3].astype(float)
    # Pixel entro TOLERANCE/2 -> completamente trasparenti
    # Pixel tra TOLERANCE/2 e TOLERANCE*2 -> sfumatura
    near = dist_sq < (TOLERANCE / 2) ** 2
    far = dist_sq > (TOLERANCE * 2) ** 2
    mid = ~(near | far)
    # Per i pixel "mid", scala alpha in base alla distanza
    mid_dist = np.sqrt(dist_sq[mid])
    mid_alpha = np.clip((mid_dist - TOLERANCE/2) / (TOLERANCE*1.5), 0, 1) * 255
    alpha[near] = 0
    alpha[mid] = mid_alpha
    alpha[far] = 255

    # Applica: crea nuovo array con alpha modificato
    new_arr = np.dstack([arr[..., :3], alpha.astype(np.uint8)])
    new_img = Image.fromarray(new_arr, 'RGBA')
    new_img.save(png_path)

    # Statistiche
    total = arr.shape[0] * arr.shape[1]
    transparent = np.sum(alpha == 0)
    return total, transparent, tuple(bg_color)

def main():
    pngs = sorted(SPRITES_DIR.glob("*_sheet.png"))
    print(f"Trovati {len(pngs)} sprite da processare")
    print(f"")
    for png in pngs:
        total, transparent, bg = process_sprite(png)
        pct = (transparent / total) * 100
        print(f"  {png.name}: sfondo={bg}, trasparenti={transparent}/{total} ({pct:.1f}%)")
    print(f"")
    print(f"Done. Tutti gli sprite sono stati post-processati.")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
fix_hd_transparency_v2.py - Rimuove sfondo bianco con soglia aggressiva.
Approccio: tutti i pixel "quasi bianchi" (R,G,B > 230) diventano trasparenti.
Mantiene i pixel del personaggio che hanno anche solo una piccola saturazione.
"""
from PIL import Image
import numpy as np
import os

HD_DIR = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/hd"

count = 0
for filename in sorted(os.listdir(HD_DIR)):
    if not filename.endswith("_hd_sheet.png"):
        continue
    filepath = os.path.join(HD_DIR, filename)
    img = Image.open(filepath).convert("RGBA")
    arr = np.array(img)
    
    # Identifica pixel bianchi: R, G, B tutti > 230 e molto vicini tra loro
    r, g, b = arr[:,:,0], arr[:,:,1], arr[:,:,2]
    # Bianco: alta luminosità e bassa saturazione
    max_channel = np.maximum(np.maximum(r, g), b)
    min_channel = np.minimum(np.minimum(r, g), b)
    saturation = max_channel.astype(int) - min_channel.astype(int)
    # Bianco se luminosità > 230 E saturazione < 15
    is_white = (max_channel > 230) & (saturation < 15)
    
    # Conta prima del fix
    white_count_before = np.sum(is_white)
    
    # Rendi trasparenti
    arr[is_white, 3] = 0
    
    # Salva
    img = Image.fromarray(arr)
    img.save(filepath)
    count += 1
    if count % 20 == 0:
        print(f"  Processed {count} sprites...")

print(f"\nDone: {count} HD sprites processed")
# Verifica uno
img2 = Image.open(os.path.join(HD_DIR, "monster_001_hd_sheet.png")).convert("RGBA")
arr2 = np.array(img2)
print(f"monster_001 after fix: alpha min={arr2[:,:,3].min()}, max={arr2[:,:,3].max()}")
print(f"Transparent pixels: {np.sum(arr2[:,:,3] == 0)} / {arr2.shape[0]*arr2.shape[1]}")

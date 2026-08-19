#!/usr/bin/env python3
"""
verify_sprites.py - Verifica integrita' di tutti gli sprite PNG generati.

Controlla per ogni file:
1. Il file esiste e non e' vuoto
2. Si apre correttamente con PIL (non corrotto)
3. Dimensioni 64x64
4. Modalita' RGBA (trasparenza)
5. Ha pixel opachi (personaggio presente)
6. Non e' completamente vuoto o completamente opaco
7. Verifica palette 16 colori
8. Verifica che alpha sia quantizzato (solo 0 o 255, no semi-trasparenti)
9. Verifica fringe (no pixel orfani ai bordi)
"""
import os
from pathlib import Path
from PIL import Image
import numpy as np

SPRITES_DIR = Path("/home/z/my-project/ArcadeMaze/assets/sprites")
SPRITE_SIZE = 64

PALETTE = [
    (12,12,12),(48,40,36),(96,80,72),(160,128,112),
    (200,180,160),(120,140,160),(80,120,100),(40,80,60),
    (160,40,40),(200,80,80),(220,160,40),(200,200,80),
    (120,200,200),(80,160,220),(160,120,200),(240,240,240)
]

CHARACTERS = ['char_mage','char_orc','char_elf','char_knight',
              'char_golem','char_dragon','char_vampire']
FRAMES = ['idle','walk0','walk1','walk2','walk3','jump']

problems = []
stats = []

def is_in_palette(rgb):
    """Verifica se un colore RGB e' nella palette 16 (approssimato)."""
    for p in PALETTE:
        # Tolleranza 8 per errori di quantizzazione
        if abs(rgb[0]-p[0]) <= 8 and abs(rgb[1]-p[1]) <= 8 and abs(rgb[2]-p[2]) <= 8:
            return True
    return False

def check_sprite(char, frame):
    """Verifica un singolo sprite PNG + JSON."""
    issues = []
    base = f"{char}_{frame}"
    png_path = SPRITES_DIR / f"{base}_sheet.png"
    json_path = SPRITES_DIR / f"{base}_meta.json"
    
    # 1. Esistenza PNG
    if not png_path.exists():
        issues.append("PNG MANCANTE")
        return issues
    
    # 2. File non vuoto
    size = png_path.stat().st_size
    if size < 100:
        issues.append(f"PNG quasi vuoto ({size} bytes)")
        return issues
    
    # 3. Apertura PNG (corruzione)
    try:
        img = Image.open(png_path)
        img.verify()  # verifica integrita'
        img = Image.open(png_path)  # riapri dopo verify
    except Exception as e:
        issues.append(f"PNG CORROTTO: {e}")
        return issues
    
    # 4. Dimensioni 64x64
    if img.size != (SPRITE_SIZE, SPRITE_SIZE):
        issues.append(f"Dimensioni sbagliate: {img.size} (atteso 64x64)")
    
    # 5. Modalita' RGBA
    if img.mode != 'RGBA':
        issues.append(f"Modalita' sbagliata: {img.mode} (atteso RGBA)")
    
    # Converti per analisi
    arr = np.array(img.convert('RGBA'))
    
    # 6. Pixel opachi (personaggio presente)
    opachi = np.sum(arr[..., 3] > 0)
    total = arr.shape[0] * arr.shape[1]
    if opachi < 50:
        issues.append(f"TROPPO POCHI pixel opachi: {opachi} (sospetto vuoto)")
    elif opachi > total * 0.95:
        issues.append(f"TROPPI pixel opachi: {opachi}/{total} (sospetto no trasparenza)")
    
    # 7. Verifica alpha quantizzato (solo 0 o 255, no semi-trasparenti)
    alpha = arr[..., 3]
    semi_trasparenti = np.sum((alpha > 0) & (alpha < 255))
    if semi_trasparenti > 0:
        issues.append(f"{semi_trasparenti} pixel semi-trasparenti (alpha 1-254)")
    
    # 8. Verifica palette 16 colori
    rgb_opachi = arr[arr[..., 3] > 0][..., :3] if opachi > 0 else np.array([]).reshape(0,3)
    if len(rgb_opachi) > 0:
        out_of_palette = 0
        for px in rgb_opachi:
            if not is_in_palette(tuple(px)):
                out_of_palette += 1
        if out_of_palette > 0:
            pct = out_of_palette / len(rgb_opachi) * 100
            if pct > 5:  # piu' del 5% fuori palette
                issues.append(f"{out_of_palette} pixel fuori palette ({pct:.1f}%)")
    
    # 9. Verifica fringe (pixel orfani ai bordi)
    # Un pixel orfano e' un pixel opaco circondato da soli pixel trasparenti
    bordo_problemi = 0
    alpha_mask = arr[..., 3] > 0
    for y in range(1, SPRITE_SIZE-1):
        for x in range(1, SPRITE_SIZE-1):
            if alpha_mask[y, x]:
                # Conta vicini opachi (8-connettivita')
                vicini = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dy == 0 and dx == 0: continue
                        if alpha_mask[y+dy, x+dx]: vicini += 1
                if vicini == 0:
                    bordo_problemi += 1
    if bordo_problemi > 20:
        issues.append(f"{bordo_problemi} pixel orfani (fringe residuo)")
    
    # 10. Verifica JSON
    if not json_path.exists():
        issues.append("JSON MANCANTE")
    else:
        try:
            import json
            with open(json_path) as f:
                meta = json.load(f)
            if meta.get('frameWidth') != SPRITE_SIZE:
                issues.append(f"JSON frameWidth sbagliato: {meta.get('frameWidth')}")
            if meta.get('frameHeight') != SPRITE_SIZE:
                issues.append(f"JSON frameHeight sbagliato: {meta.get('frameHeight')}")
            if meta.get('columns') != 1:
                issues.append(f"JSON columns sbagliato: {meta.get('columns')}")
            if meta.get('rows') != 1:
                issues.append(f"JSON rows sbagliato: {meta.get('rows')}")
        except Exception as e:
            issues.append(f"JSON corrotto: {e}")
    
    stats.append({
        'char': char,
        'frame': frame,
        'opachi': int(opachi),
        'total': total,
        'pct_opachi': opachi/total*100,
        'size_bytes': size,
    })
    
    return issues

# --- Esegui verifica ---
print("=" * 80)
print("VERIFICA INTEGRITA' SPRITE PNG PERSONAGGI GIOCABILI")
print("=" * 80)
print()

total_ok = 0
total_problems = 0
for char in CHARACTERS:
    print(f"[{char}]")
    char_ok = 0
    char_problems = 0
    for frame in FRAMES:
        issues = check_sprite(char, frame)
        status = "OK" if not issues else "PROBLEMA"
        pct = stats[-1]['pct_opachi'] if stats else 0
        print(f"  {frame:8s}: {status:8s} (opachi={pct:5.1f}%)")
        if issues:
            char_problems += 1
            for iss in issues:
                print(f"           -> {iss}")
        else:
            char_ok += 1
    print(f"  Totale {char}: {char_ok}/6 OK, {char_problems}/6 problemi")
    total_ok += char_ok
    total_problems += char_problems
    print()

print("=" * 80)
print(f"RISULTATO FINALE: {total_ok}/{len(CHARACTERS)*6} sprite OK")
print(f"Problemi totali: {total_problems}")
print("=" * 80)

# Salva report
if stats:
    print()
    print("=== Statistiche dettagliate ===")
    print(f"{'Personaggio':<15} {'Frame':<8} {'Opachi':>8} {'%Opachi':>8} {'Bytes':>8}")
    print("-" * 60)
    for s in stats:
        print(f"{s['char']:<15} {s['frame']:<8} {s['opachi']:>8} {s['pct_opachi']:>7.1f}% {s['size_bytes']:>8}")

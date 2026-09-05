#!/usr/bin/env python3
"""
fix_hd_transparency.py - Rimuove lo sfondo bianco dagli HD sprite.
Gli sprite AI sono generati con sfondo bianco invece di trasparenza.
Questo script fa chroma key del bianco per renderlo trasparente.
"""
from PIL import Image
import os

HD_DIR = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/hd"

# Soglia per considerare un pixel "sfondo bianco"
WHITE_THRESHOLD = 230  # R, G, B tutti > di questo valore
EDGE_TOLERANCE = 5  # tolleranza per i bordi (non rimuovere bianchi vicini a colori)

count = 0
for filename in sorted(os.listdir(HD_DIR)):
    if not filename.endswith("_hd_sheet.png"):
        continue
    filepath = os.path.join(HD_DIR, filename)
    img = Image.open(filepath).convert("RGBA")
    width, height = img.size
    pixels = img.load()
    
    # Identifica i pixel di sfondo bianco (con BFS dal bordo)
    # per non rimuovere bianchi che sono parte del personaggio
    visited = [[False] * width for _ in range(height)]
    to_process = []
    
    # Partiamo dal bordo
    for x in range(width):
        for y in [0, height - 1]:
            if not visited[y][x]:
                r, g, b, a = pixels[x, y]
                if a > 0 and r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                    to_process.append((x, y))
                    visited[y][x] = True
    for y in range(height):
        for x in [0, width - 1]:
            if not visited[y][x]:
                r, g, b, a = pixels[x, y]
                if a > 0 and r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                    to_process.append((x, y))
                    visited[y][x] = True
    
    # BFS flood fill dal bordo per rimuovere il bianco connesso al bordo
    while to_process:
        x, y = to_process.pop()
        pixels[x, y] = (255, 255, 255, 0)  # trasparente
        # Esplora i vicini
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx]:
                r, g, b, a = pixels[nx, ny]
                if a > 0 and r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                    visited[ny][nx] = True
                    to_process.append((nx, ny))
    
    img.save(filepath)
    count += 1
    if count % 20 == 0:
        print(f"  Processed {count} sprites...")

print(f"\nDone: {count} HD sprites processed with transparency fix")

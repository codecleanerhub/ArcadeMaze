#!/usr/bin/env python3
"""Task 61 — ricolorazione GRATUITA (0 gen) della fiamma blu del Drago.

Ruota la tinta del sheet proj_fireball_sheet.png (Task 60b) di ~198 gradi:
- arancio -> blu profondo (fiamma fredda)
- giallo/nucleo caldo -> ciano/bianco ghiaccio
Preserva luminanza e alpha (flicker identico al rosso).
Output: godot/assets/sprites/projectiles/proj_fireball_blue_sheet.png
"""
import colorsys
import os

BASE = "/home/z/my-project/ArcadeMaze"
SRC = os.path.join(BASE, "godot/assets/sprites/projectiles/proj_fireball_sheet.png")
DST = os.path.join(BASE, "godot/assets/sprites/projectiles/proj_fireball_blue_sheet.png")
HUE_SHIFT = 0.55  # ~198 gradi

from PIL import Image

img = Image.open(SRC).convert("RGBA")
px = img.load()
changed = 0
for y in range(img.height):
        for x in range(img.width):
                r, g, b, a = px[x, y]
                if a == 0:
                        continue
                h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                h = (h + HUE_SHIFT) % 1.0
                # fuoco freddo: leggera desaturazione + niente slittamento
                # del valore (il nucleo resta luminoso)
                s = min(1.0, s * 0.92)
                r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v)
                px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
                changed += 1
img.save(DST)
print(f"[blue-flame] {changed} px ricolorati -> {DST}")

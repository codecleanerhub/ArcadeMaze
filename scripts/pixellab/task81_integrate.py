#!/usr/bin/env python3
"""TASK 81 — post-processing grafiche fantasmi/celle zombie (0 generazioni).

1) FANTASMA: ghost_sheet_white.png (nativo) -> varianti ROSSA e VERDE con
   tint per-canale (pattern 61b del recolor, preserva luminanza/profilo
   shading e alpha): il fantasma bianco ha ombre grigio-azzurre; il tint
   moltiplica i canali cosi' il chiaro/scuro resta proporzionale e i fori
   (occhi/bocca, quasi neri) restano scuri.
     rosso:  (r, g*0.30, b*0.28)
     verde:  (r*0.34, g, b*0.32)
2) CELLA ZOMBIE: se il blocco non e' full-bleed (margini trasparenti attorno),
   crop sul bounding box opaco + resize NEAREST a 64x64 (deve coprire tutta
   la cella muro per nascondere le braccia a riposo).
3) QA numerica: dimensioni sheet (256x64) e cella (64x64), 4 frame distinti,
   tint != bianco, full-bleed check.
4) Preview 4x NEAREST -> /home/z/my-project/download/task81_preview.png
   (VLM check prima dell'integrazione in gioco).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image

ENV = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/env"
PREVIEW = "/home/z/my-project/download/task81_preview.png"

WHITE = os.path.join(ENV, "ghost_sheet_white.png")
RED = os.path.join(ENV, "ghost_sheet_red.png")
GREEN = os.path.join(ENV, "ghost_sheet_green.png")
CELL = os.path.join(ENV, "zombie_cell.png")
ARMS = os.path.join(ENV, "zombie_arms_sheet.png")

errors: list[str] = []


def tint_channels(img: Image.Image, kr: float, kg: float, kb: float) -> Image.Image:
    out = img.copy()
    px = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            px[x, y] = (int(r * kr), int(g * kg), int(b * kb), a)
    return out


def frame_stats(sheet: Image.Image, n: int = 4, frame_px: int = 64):
    """Ritorna (coverage_px, hash-ish somma pixel) per ogni frame."""
    stats = []
    for i in range(n):
        box = (i * frame_px, 0, (i + 1) * frame_px, frame_px)
        f = sheet.crop(box)
        opaque = sum(1 for p in f.getdata() if p[3] > 0)
        sig = sum(p[0] + p[1] * 3 + p[2] * 7 + p[3] * 11 for p in f.getdata())
        stats.append((opaque, sig))
    return stats


# ------------------------------------------------ 1) tint fantasma
white = Image.open(WHITE).convert("RGBA")
if white.size != (256, 64):
    errors.append(f"ghost_sheet_white: atteso 256x64, trovato {white.size}")
red = tint_channels(white, 1.0, 0.30, 0.28)
red.save(RED)
green = tint_channels(white, 0.34, 1.0, 0.32)
green.save(GREEN)
print(f"[tint] red -> {RED}")
print(f"[tint] green -> {GREEN}")

# i fori devono restare scuri nelle varianti: campiona il pixel piu' scuro
for name, path in (("red", RED), ("green", GREEN)):
    im = Image.open(path).convert("RGBA")
    darks = [p for p in im.getdata() if p[3] > 200 and p[0] + p[1] + p[2] < 120]
    if not darks:
        errors.append(f"{name}: nessun pixel scuro opaco (occhi/bocca persi?)")

# ------------------------------------------------ 2) cella full-bleed
cell = Image.open(CELL).convert("RGBA")
if cell.size != (64, 64):
    # crop bbox opaco + resize NEAREST
    bbox = cell.getbbox()
    if bbox is None:
        errors.append("zombie_cell: immagine vuota")
    else:
        cell = cell.crop(bbox).resize((64, 64), Image.NEAREST)
        cell.save(CELL)
        print(f"[cell] ricavata full-bleed da bbox {bbox}")
opaque_ratio = sum(1 for p in cell.getdata() if p[3] > 0) / (64 * 64)
if opaque_ratio < 0.985:
    errors.append(f"zombie_cell: copertura {opaque_ratio:.1%} < 98.5% "
                  "(le braccia a riposo resterebbero visibili)")
else:
    print(f"[cell] full-bleed OK ({opaque_ratio:.1%} opaco)")

# ------------------------------------------------ 3) QA sheet
for name, path in (("ghost_white", WHITE), ("zombie_arms", ARMS)):
    sh = Image.open(path).convert("RGBA")
    if sh.size != (256, 64):
        errors.append(f"{name}: atteso 256x64, trovato {sh.size}")
        continue
    st = frame_stats(sh)
    sigs = [s[1] for s in st]
    if len(set(sigs)) < 4:
        errors.append(f"{name}: frame non distinti ({sigs})")
    cov0 = st[0][0] / (64 * 64)
    print(f"[qa] {name}: frame opachi {[s[0] for s in st]} "
          f"(frame0 {cov0:.1%})")

# ------------------------------------------------ 4) preview 4x
SCALE = 4
prev_w = 4 * 64 * SCALE  # 4 colonne: ghost white | red | green | arms
prev_h = 2 * 64 * SCALE  # 2 righe: riga0 = sheet 4 frame, riga1 = cell
canvas = Image.new("RGBA", (prev_w, prev_h), (24, 20, 28, 255))


def blit(dst, src, cell_x, cell_y):
    big = src.resize((src.width * SCALE, src.height * SCALE), Image.NEAREST)
    dst.paste(big, (cell_x * 64 * SCALE, cell_y * 64 * SCALE), big)


# riga 0: i 3 sheet fantasma + braccia (primi 2 frame ciascuno, per larghezza)
row0 = [
    Image.open(WHITE).convert("RGBA").crop((0, 0, 128, 64)),
    Image.open(RED).convert("RGBA").crop((0, 0, 128, 64)),
    Image.open(GREEN).convert("RGBA").crop((0, 0, 128, 64)),
    Image.open(ARMS).convert("RGBA").crop((0, 0, 128, 64)),
]
for i, im in enumerate(row0):
    blit(canvas, im, i, 0)

# riga 1: cella (frame anima statica) + braccia frame 2..3 + composito
# cella+braccia estese (mock: braccia disegnate a destra del blocco)
composite = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
arms_f2 = Image.open(ARMS).convert("RGBA").crop((128, 0, 192, 64))
composite.paste(arms_f2, (64, 0), arms_f2)
composite.paste(cell, (0, 0), cell)
row1 = [cell, Image.open(ARMS).convert("RGBA").crop((128, 0, 192, 64)),
        composite, composite]
for i, im in enumerate(row1):
    blit(canvas, im, i, 1)

canvas.save(PREVIEW)
print(f"[preview] {PREVIEW}")

if errors:
    print("\n[QA] ERRORI:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print("\n[QA] TUTTO OK")

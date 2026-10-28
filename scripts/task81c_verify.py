#!/usr/bin/env python3
"""task81c_verify.py — verifica pixel GEMME -30% (TASK 81c).

Legge i dump CAP81 dello shot_task81 (posizioni+tipi dei tesori), misura
il bounding box dei pixel colorati di ogni tesoro nelle screenshot
1920x1080 e confronta la dimensione delle GEMME (zaffiro blu = t3, rubino
rosso = t4) con quella degli altri tesori (corona t0 / oro t1).

Attesa: bbox gemme ~= 0.70 x bbox altri (canvas 73.6 -> 51.5px nel maze).

Cella -> pixel: centro = (c*64+32, 80 + r*64 + 32); il tesoro e' disegnato
centrato sulla cella (draw_size anche oltre i 64px della cella).
"""
import json
import sys
from PIL import Image

DOWNLOAD = "/home/z/my-project/download/"
TILE = 64
UI_H = 80

# tipi tesoro: 0 CROWN, 1 GOLD, 2 CHEST, 3 GEM, 4 RUBY
GEM_TYPES = {3, 4}
OTHER_TYPES = {0, 1}  # corona + oro: gold brillante, confronto pulito


def cell_center(c, r):
    return c * TILE + TILE // 2, UI_H + r * TILE + TILE // 2


def measure_bbox(img, cx, cy, kind, win=56):
    """bbox dei pixel del colore caratteristico del tipo dentro la
    finestra win x win centrata sul centro cella. Ritorna (w, h, n)."""
    px = img.load()
    xs, ys = [], []
    for y in range(max(0, cy - win), min(img.height, cy + win)):
        for x in range(max(0, cx - win), min(img.width, cx + win)):
            r, g, b = px[x, y][:3]
            hit = False
            if kind == 3:  # zaffiro blu
                hit = b > 110 and b > r + 40 and b > g + 30
            elif kind == 4:  # rubino rosso
                hit = r > 110 and r > g + 40 and r > b + 40
            elif kind in (0, 1):  # oro/corona brillante
                hit = r > 130 and g > 95 and b < r - 45
            if hit:
                xs.append(x)
                ys.append(y)
    if not xs:
        return 0, 0, 0
    return max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, len(xs)


def main():
    caps = []
    with open("/tmp/shot81.log", "r", errors="replace") as f:
        for line in f:
            if line.startswith("CAP81 "):
                caps.append(json.loads(line[6:]))
    if not caps:
        print("NESSUN dump CAP81 trovato")
        return 2

    gem_sizes = []
    other_sizes = []
    ok = True
    for cap in caps:
        if "_later" in cap["file"]:
            continue  # solo gli scatti con tesori ben visibili
        img = Image.open(DOWNLOAD + cap["file"]).convert("RGB")
        print(f"\n== {cap['file']} (livello {cap['level']}) ==")
        for tr in cap["treasures"]:
            c, r, t = tr["c"], tr["r"], tr["t"]
            cx, cy = cell_center(c, r)
            w, h, n = measure_bbox(img, cx, cy, t)
            name = {0: "CROWN", 1: "GOLD", 2: "CHEST", 3: "GEM", 4: "RUBY"}[t]
            print(f"  tesoro {name:5s} cella ({c:2d},{r:2d}) -> bbox {w}x{h}px ({n} px)")
            if t in GEM_TYPES and w > 0:
                gem_sizes.append((w + h) / 2.0)
            elif t in OTHER_TYPES and w > 0:
                other_sizes.append((w + h) / 2.0)

    if not gem_sizes or not other_sizes:
        print(f"\nMANCANO misure (gem={len(gem_sizes)}, other={len(other_sizes)})")
        return 2
    gem_avg = sum(gem_sizes) / len(gem_sizes)
    other_avg = sum(other_sizes) / len(other_sizes)
    ratio = gem_avg / other_avg
    print(f"\ngemme (GEM+RUBY): media {gem_avg:.1f}px su {len(gem_sizes)} misure")
    print(f"altri  (CROWN+GOLD): media {other_avg:.1f}px su {len(other_sizes)} misure")
    print(f"rapporto gemme/altri = {ratio:.3f} (atteso ~0.70, range OK 0.55-0.85)")
    if 0.55 <= ratio <= 0.85:
        print("VERIFICA GEMME -30%: PASS")
        return 0
    print("VERIFICA GEMME -30%: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())

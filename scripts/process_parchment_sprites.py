#!/usr/bin/env python3
"""TASK 35 — Processing PERGAMENE EVENTO: chroma-key → PNG trasparenti.

Pipeline (adattata da process_relic_icons.py Task 23):
  * flood locale con GUARDIA DI FAMIGLIA COLORE + continuità (magenta per
    la pergamena ambra/terremoto, CIANO per quella viola/voragini);
  * frangia semi-trasparente 2px (guardia rilassata) + despill;
  * trim + margine 8% + crop quadrato + resize 128 (dimensioni dei PNG
    tesoro: il collectible si disegna a 48px come i tesori);
  * COMPOSITO DETERMINISTICO del piccolo SIMBOLO in alto a destra:
    - quake_scroll : zigzag sismico (3 impulsi) arancio fuoco
    - chasm_scroll : spirale archimedea viola psichico
    (piccoli, ~26px su canvas 128, centrati sull'angolo alto-destro del
    rotolo, con outline scura per la leggibilità);
  * beacon_glow.png : gradiente radiale bianco→trasparente (telegrafo
    pre-apparizione; viene tinto via modulate dal controller).

Output: godot/assets/sprites/parchment/{quake_scroll,chasm_scroll,beacon_glow}.png
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from collections import deque

RAW_DIR = Path("/tmp/parchment_gen")
OUT_DIR = Path("/home/z/my-project/ArcadeMaze/godot/assets/sprites/parchment")

ITEMS = {
    # id: (cyan_key, symbol_color, glow_color)
    "quake_scroll": (False, (255, 122, 26), (255, 160, 60)),
    "chasm_scroll": (True, (178, 102, 255), (200, 140, 255)),
}

FINAL_SIDE = 128
MARGIN_FRAC = 0.08

# --- famiglia magenta/vino (per quake: pergamena ambra NON passa mai) ---
MAG_R_OVER_G = 25.0
MAG_B_OVER_G = -8.0
# --- famiglia ciano (per chasm: pergamena viola NON passa mai) ---
CYA_B_OVER_R = 25.0
CYA_G_OVER_R = 10.0

LOCAL_TOL = 30.0


def family_mask(rgb: np.ndarray, cyan: bool, loose: bool = False) -> np.ndarray:
    r = rgb[..., 0]
    g = rgb[..., 1]
    b = rgb[..., 2]
    if cyan:
        ro = CYA_B_OVER_R * (0.5 if loose else 1.0)
        go = CYA_G_OVER_R * (0.5 if loose else 1.0)
        return (b > r + ro) & (g > r + go)
    ro = MAG_R_OVER_G * (0.5 if loose else 1.0)
    bo = MAG_B_OVER_G if not loose else -20.0
    return (r > g + ro) & (b > g + bo)


def local_flood(rgb: np.ndarray, cyan: bool) -> np.ndarray:
    """BFS dal bordo: famiglia colore + continuità col pixel genitore."""
    h, w, _ = rgb.shape
    fam = family_mask(rgb, cyan)
    bg = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if fam[y, x] and not bg[y, x]:
                bg[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if fam[y, x] and not bg[y, x]:
                bg[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        px = rgb[y, x]
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if ny < 0 or ny >= h or nx < 0 or nx >= w:
                continue
            if bg[ny, nx] or not fam[ny, nx]:
                continue
            if float(np.abs(rgb[ny, nx] - px).max()) <= LOCAL_TOL:
                bg[ny, nx] = True
                queue.append((ny, nx))
    return bg


def chroma_key(img: Image.Image, cyan: bool) -> Image.Image:
    """Sfondo → alpha 0; frangia 2px con guardia rilassata; despill."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    bg = local_flood(rgb, cyan)
    h, w, _ = rgb.shape
    alpha = np.where(bg, 0.0, 255.0)

    # frangia: 2 iterazioni di erosione della maschera sfondo (bordi morbidi)
    fringe = bg.copy()
    for _ in range(2):
        er = fringe.copy()
        er[1:, :] |= fringe[:-1, :]
        er[:-1, :] |= fringe[1:, :]
        er[:, 1:] |= fringe[:, :-1]
        er[:, :-1] |= fringe[:, 1:]
        fringe = er
    loose = family_mask(rgb, cyan, loose=True)
    fringe = fringe & ~bg & loose
    alpha[fringe] = 110.0

    # despill: i pixel semitrasparenti tendono al colore della chiave
    key = np.array([255.0, 0.0, 255.0]) if not cyan else np.array([0.0, 255.0, 255.0])
    for _ in range(2):
        spill = (np.abs(rgb - key).max(axis=2) < 90.0) & (alpha > 0) & (alpha < 255)
        rgb[spill] = rgb[spill] * 0.82 + np.array([60.0, 45.0, 35.0]) * 0.18

    out = np.dstack([rgb, alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def trim_margin_square(img: Image.Image) -> Image.Image:
    """Ritaglia sul contenuto + margine 8% + crop quadrato centrato."""
    alpha = np.asarray(img)[:, :, 3]
    ys, xs = np.where(alpha > 8)
    if len(xs) == 0:
        return img
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    mx, my = int(cw * MARGIN_FRAC), int(ch * MARGIN_FRAC)
    x0, y0 = max(0, x0 - mx), max(0, y0 - my)
    x1, y1 = min(img.width - 1, x1 + mx), min(img.height - 1, y1 + my)
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    side = max(cw, ch)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sx = max(0, min(img.width - side, cx - side // 2))
    sy = max(0, min(img.height - side, cy - side // 2))
    return img.crop((sx, sy, sx + side, sy + side))


def make_symbol(canvas_side: int, kind: str, color, glow) -> Image.Image:
    """Piccolo simbolo in alto a destra: zigzag sismico o spirale."""
    s = canvas_side
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # il simbolo vive nell'angolo alto-destro, ~22% del canvas
    cx, cy = int(s * 0.80), int(s * 0.26)
    half = int(s * 0.115)
    dark = (30, 18, 10, 235)

    # alone luminoso (glow morbido)
    glow_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for rr, aa in ((half + int(s * 0.05), 70), (half + int(s * 0.02), 110)):
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   fill=(glow[0], glow[1], glow[2], aa))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(2.5))
    layer = Image.alpha_composite(layer, glow_layer)
    d = ImageDraw.Draw(layer)

    if kind == "quake":
        # zigzag sismico: 3 picchi con impulso iniziale forte
        pts = []
        n = 7
        for i in range(n):
            t = i / float(n - 1)
            x = cx - half + t * 2.0 * half
            y = cy + (math.sin(t * 3.0 * math.pi) * half * 0.95)
            pts.append((x, y))
        # traccia spessa scura (outline) + traccia colorata
        d.line(pts, fill=dark, width=max(3, s // 26), joint="curve")
        d.line(pts, fill=(color[0], color[1], color[2], 255),
               width=max(2, s // 36), joint="curve")
    else:
        # spirale archimedea
        pts = []
        turns = 2.6
        steps = 90
        for i in range(steps):
            t = i / float(steps)
            ang = t * turns * 2.0 * math.pi - math.pi / 2.0
            r = 2.0 + t * half
            pts.append((cx + math.cos(ang) * r * 0.86,
                        cy + math.sin(ang) * r * 0.86))
        d.line(pts, fill=dark, width=max(3, s // 26), joint="curve")
        d.line(pts, fill=(color[0], color[1], color[2], 255),
               width=max(2, s // 36), joint="curve")
        # centro scuro = il "pozzo"
        d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=dark)
    return layer


def make_beacon_glow() -> Image.Image:
    """Gradiente radiale bianco → trasparente (tinto via modulate)."""
    s = 128
    arr = np.zeros((s, s, 4), dtype=np.uint8)
    cx = cy = (s - 1) / 2.0
    max_r = s / 2.0
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - cx, y - cy) / max_r
            a = max(0.0, 1.0 - r) ** 2.2
            arr[y, x] = (255, 255, 255, int(a * 255.0))
    return Image.fromarray(arr, "RGBA")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for item_id, (cyan, sym_color, glow_color) in ITEMS.items():
        raw_path = RAW_DIR / f"{item_id}.png"
        if not raw_path.is_file():
            print(f"SKIP {item_id}: raw non trovato ({raw_path})")
            continue
        img = Image.open(raw_path).convert("RGB")
        keyed = chroma_key(img, cyan)
        square = trim_margin_square(keyed)
        final = square.resize((FINAL_SIDE, FINAL_SIDE), Image.LANCZOS)
        # composita il simbolo in alto a destra
        symbol = make_symbol(FINAL_SIDE, item_id, sym_color, glow_color)
        final = Image.alpha_composite(final, symbol)
        out_path = OUT_DIR / f"{item_id}.png"
        final.save(out_path)
        cov = float((np.asarray(final)[:, :, 3] > 8).mean())
        print(f"OK {item_id}: {out_path} {FINAL_SIDE}x{FINAL_SIDE} "
              f"(copertura {cov:.0%})")
    beacon = make_beacon_glow()
    beacon.save(OUT_DIR / "beacon_glow.png")
    print(f"OK beacon_glow: {OUT_DIR / 'beacon_glow.png'} 128x128")


if __name__ == "__main__":
    main()

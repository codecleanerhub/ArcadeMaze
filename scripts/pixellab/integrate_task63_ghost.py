#!/usr/bin/env python3
"""Task 63a — post-processing ghost reaper PixelLab v2.

Eseguito DOPO `pl_run.py anim defs_task63 ghost_reaper`:
  1. alpha ectoplasmatica: il vecchio sheet incorporava alpha 184/255
     (~0.72) sul corpo; il codice GhostReaper.gd moltiplica ulteriormente
     la modulate (pulsazione 0.78-0.92). Per identita' visiva 1:1 il nuovo
     PNG deve portare la stessa alpha incorporata.
  2. meta completo: pl_integrate.write_anim_sheet scrive il meta MINIMO
     (columns/rows/anchor); il ghost usa SpriteManager con animazioni
     nominali (walk 130ms, death 1 frame) -> riscrivo il meta nel formato
     completo IDENTICO all'originale.
  3. variante rossa P2: hue shift verde ectoplasma -> rosso sangue
     (~232 gradi, pattern recolor_fireball_blue.py 61b, 0 generazioni).
  4. sync mirror legacy per tutti i file scritti.

Uso:
  python3 integrate_task63_ghost.py --prepare-anchor   # PRIMA del run
  python3 integrate_task63_ghost.py                    # DOPO il run
"""
from __future__ import annotations

import colorsys
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pl_integrate
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "ghost_reaper")

GHOST_PNG = os.path.join(pl_integrate.GODOT_SPRITES, "ghost_reaper_sheet.png")
GHOST_META = os.path.join(pl_integrate.GODOT_SPRITES, "ghost_reaper_meta.json")
RED_PNG = os.path.join(pl_integrate.GODOT_SPRITES, "ghost_reaper_red_sheet.png")
RED_META = os.path.join(pl_integrate.GODOT_SPRITES, "ghost_reaper_red_meta.json")

# Alpha del vecchio sheet: corpo a ~184/255 (0.722) — verificata con
# istogramma (bucket 5: 5436/6584 px visibili).
ECTOPLASM_ALPHA = 184.0 / 255.0

# Shift di tinta verde ectoplasma (~132 gradi) -> rosso sangue (~4 gradi):
# 232 gradi = 0.644 in unita' colorsys (pattern 61b: shift unico globale,
# preserva luminanza e alpha).
HUE_SHIFT_RED = 232.0 / 360.0

# Meta completo (formato SpriteManager con animazioni nominali) — identico
# all'originale pre-v2: walk 130ms e' l'identita' del fantasma.
def _meta(image_name: str) -> dict:
    return {
        "image": image_name,
        "frameWidth": 64,
        "frameHeight": 64,
        "columns": 4,
        "rows": 1,
        "anchor": {"x": 32, "y": 56},
        "animations": {
            "idle":   {"row": 0, "frames": 4, "frameDuration": 200},
            "walk":   {"row": 0, "frames": 4, "frameDuration": 130},
            "attack": {"row": 0, "frames": 4, "frameDuration": 90},
            "death":  {"row": 0, "frames": 1, "frameDuration": 120},
        },
    }


def prepare_anchor() -> None:
    """Anchor colore dal frame 0 del vecchio sheet, alpha normalizzata."""
    os.makedirs(OUT, exist_ok=True)
    old = Image.open(GHOST_PNG).convert("RGBA")
    f0 = old.crop((0, 0, 64, 64))
    # normalizza alpha -> 255 (reference colore pieno, non slavato)
    px = f0.load()
    for y in range(64):
        for x in range(64):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a > 60 else (0, 0, 0, 0)
    # upscale NEAREST su canvas 256x256 centrato (ricetta _color_anchor_png)
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    big = f0.resize((256, 256), Image.NEAREST)
    canvas.paste(big, (0, 0), big)
    dst = os.path.join(OUT, "anchor_custom.png")
    canvas.save(dst, "PNG")
    print(f"[anchor] {dst} (da frame0 vecchio sheet, alpha->255)")


def apply_ectoplasm_alpha(path: str) -> None:
    img = Image.open(path).convert("RGBA")
    px = img.load()
    changed = 0
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (r, g, b, int(round(a * ECTOPLASM_ALPHA)))
                changed += 1
    img.save(path, "PNG")
    print(f"[ectoplasm] {path}: alpha *= {ECTOPLASM_ALPHA:.3f} su {changed} px")


def make_red_variant() -> None:
    """Deriva ghost_reaper_red dal nuovo sheet verde (0 generazioni)."""
    pl_integrate.backup_original(RED_PNG)
    img = Image.open(GHOST_PNG).convert("RGBA")
    px = img.load()
    changed = 0
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            h = (h + HUE_SHIFT_RED) % 1.0
            # rosso sangue: leggera desaturazione (pattern fiamma blu 61b)
            s = min(1.0, s * 0.94)
            r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v)
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
            changed += 1
    img.save(RED_PNG, "PNG")
    print(f"[red] {RED_PNG}: {changed} px ricolorati (shift {HUE_SHIFT_RED*360:.0f} gradi)")


def write_meta(path: str, image_name: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(_meta(image_name), f, indent=2)
    print(f"[meta] {path} (formato completo, walk 130ms)")


def sync_mirror(rel: str) -> None:
    abs_path = os.path.join(pl_integrate.GODOT_SPRITES, rel)
    pl_integrate._sync_mirror(rel, abs_path)


def main() -> None:
    if "--prepare-anchor" in sys.argv:
        prepare_anchor()
        return

    if not os.path.isfile(GHOST_PNG):
        raise SystemExit(f"manca {GHOST_PNG} — lanciare prima pl_run.py anim")

    # 1) alpha ectoplasmatica sul sheet verde
    apply_ectoplasm_alpha(GHOST_PNG)
    # 2) meta completo (write_anim_sheet ha scritto quello minimo)
    write_meta(GHOST_META, "ghost_reaper_sheet.png")
    # 3) variante rossa dal verde (alpha gia' applicata, preservata)
    make_red_variant()
    write_meta(RED_META, "ghost_reaper_red_sheet.png")
    # 4) mirror legacy (PNG + meta, entrambe le varianti)
    for rel in ("ghost_reaper_sheet.png", "ghost_reaper_meta.json",
                "ghost_reaper_red_sheet.png", "ghost_reaper_red_meta.json"):
        sync_mirror(rel)
    print("[task63a] post-processing COMPLETO")


if __name__ == "__main__":
    main()

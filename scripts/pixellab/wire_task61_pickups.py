#!/usr/bin/env python3
"""Task 61 — pickup PNG GRATUITI (0 generazioni) per le armi elementali.

Copia/ritaglia da PNG esistenti nel progetto per collegare subito il
pickup a terra di 9/13 armi elementali. Restano per il 61c (PixelLab):
throwing_sword, fire_staff, ice_lance, ice_arrow.

- throwing_axe       <- relics/axe.png            (riuso identico)
- halberd_throw      <- relics/halberd.png        (riuso identico)
- golem_hammer_throw <- relics/golem_hammer.png   (riuso identico)
- blood_dart         <- relics/vampire_blade.png  (riuso identito, dardo)
- thrown_boulder     <- projectiles/proj_boulder.png (riuso identico)
- flame_ember        <- frame 0 proj_fireball_sheet, centrato 128
- fireball_red       <- frame 0 proj_fireball_sheet, centrato 128
- flame_blue         <- frame 0 proj_fireball_blue_sheet, centrato 128
- fire_maelstrom     <- frame 0 proj_dragon_breath_sheet, centrato 128
"""
import os

from PIL import Image

BASE = "/home/z/my-project/ArcadeMaze"
REL = os.path.join(BASE, "godot/assets/sprites/relics")
PROJ = os.path.join(BASE, "godot/assets/sprites/projectiles")

copies = {
    "throwing_axe": os.path.join(REL, "axe.png"),
    "halberd_throw": os.path.join(REL, "halberd.png"),
    "golem_hammer_throw": os.path.join(REL, "golem_hammer.png"),
    "blood_dart": os.path.join(REL, "vampire_blade.png"),
    "thrown_boulder": os.path.join(PROJ, "proj_boulder.png"),
}
for dst, src in copies.items():
        img = Image.open(src).convert("RGBA")
        img.save(os.path.join(REL, dst + ".png"))
        print(f"[pickup] {dst} <- {os.path.basename(src)} (copia)")

frames = {
    "flame_ember": (os.path.join(PROJ, "proj_fireball_sheet.png"), 0.62),
    "fireball_red": (os.path.join(PROJ, "proj_fireball_sheet.png"), 1.0),
    "flame_blue": (os.path.join(PROJ, "proj_fireball_blue_sheet.png"), 1.0),
    "fire_maelstrom": (os.path.join(PROJ, "proj_dragon_breath_sheet.png"), 1.05),
}
for dst, (src, scale) in frames.items():
        sheet = Image.open(src).convert("RGBA")
        f0 = sheet.crop((0, 0, 64, 64))
        # bbox del contenuto del frame
        bbox = f0.getbbox()
        core = f0.crop(bbox)
        # canvas 128 con il nucleo scalato al 75% (convenzione pickup)
        canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        side = int(128 * 0.75 * scale)
        core.thumbnail((side, side), Image.LANCZOS)
        canvas.paste(core, ((128 - core.size[0]) // 2,
                        (128 - core.size[1]) // 2), core)
        canvas.save(os.path.join(REL, dst + ".png"))
        print(f"[pickup] {dst} <- frame0 di {os.path.basename(src)} "
              f"(scala {scale})")

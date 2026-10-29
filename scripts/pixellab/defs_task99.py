#!/usr/bin/env python3
"""Definizioni TASK 99 (LEVEL UP) — grafica del sistema in PixelLab.

Report Task 98 §4.5: "la grafica del sistema sarà generata interamente con
PixelLab per tenere la qualità al livello delle card reliquia e delle
pergamene: le otto icone 64×64 delle abilità (cuore per l'energia, batteria
o polmoni per la stamina, stivale alato per la rapidità, spada per il
danno, caricatore per i colpi, quadrifoglio per la fortuna, croce medicinale
per la rigenerazione, doppia freccia verso l'alto per il salto), il frame
della modale in pietra scura con rifiniture in ottone, la scritta LEVEL UP!
in pixel-font dorato e l'effetto fulmine in quattro frame".

Entità (qui: 10 statici + 1 anim = 15 gen; la scritta dorata "LEVEL UP!"
ha script dedicato gen_task99_title.py per l'aspect largo):
  1-8) skill_<id>      — icone 64×64 (target skills/)
  9)   levelup_stone   — tile pietra scura per il riempimento della card
  10)  levelup_corner  — angolo decorato in ottone (flip x4 in game)
  11)  levelup_bolt    — fulmine bianco-oro 4 frame 64px (anim)

La modale carica le icone PNG-first (già cablato in FASE 2: _icon_texture).
"""
from __future__ import annotations

ENTITIES: dict = {
    # --- 1) Energia Vitale: cuore rosso gloss (anchor: ui_heart.png) -------
    "skill_energy": {
        "kind": "static",
        "target": "skills/skill_energy.png",
        "color_image": "/home/z/my-project/ArcadeMaze/godot/assets/sprites/ui_heart.png",
        "description": (
            "single glossy vibrant red heart icon with a bright highlight "
            "and a dark outline, perfectly centered, plain simple item icon "
            "on empty background, fantasy pixel art item pickup, readable "
            "silhouette, retro arcade style, crisp pixel art, NO text NO "
            "UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 101,
        "view": None,
        "max_colors": 48,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, blue heart, "
            "green heart, text, ui, watermark"
        ),
    },
    # --- 2) Resistenza: saetta verde in tondo smeraldo ---------------------
    "skill_stamina": {
        "kind": "static",
        "target": "skills/skill_stamina.png",
        "description": (
            "glowing green lightning bolt icon standing inside a small round "
            "emerald badge with a dark green rim, perfectly centered, plain "
            "simple item icon on empty background, fantasy pixel art item "
            "pickup, readable silhouette, retro arcade style, crisp pixel "
            "art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 103,
        "view": None,
        "max_colors": 48,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, red bolt, blue "
            "bolt, text, ui, watermark"
        ),
    },
    # --- 3) Salto Aggiuntivo: doppia freccia verso l'alto ------------------
    "skill_jump": {
        "kind": "static",
        "target": "skills/skill_jump.png",
        "description": (
            "double chevron arrow pointing up, two stacked cyan up-arrows "
            "with bright white edges and a dark outline, perfectly centered, "
            "plain simple item icon on empty background, fantasy pixel art "
            "item pickup, readable silhouette, retro arcade style, crisp "
            "pixel art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 107,
        "view": None,
        "max_colors": 40,
        "coverage": (5.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, down arrow, "
            "text, ui, watermark"
        ),
    },
    # --- 4) Potenza di Fuoco: spada fiammeggiante ---------------------------
    "skill_firepower": {
        "kind": "static",
        "target": "skills/skill_firepower.png",
        "description": (
            "upright fantasy sword icon with a bright steel blade and a "
            "small orange flame rising along the edge, golden crossguard, "
            "dark outline, perfectly centered, plain simple item icon on "
            "empty background, fantasy pixel art item pickup, readable "
            "silhouette, retro arcade style, crisp pixel art, NO text NO "
            "UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 109,
        "view": None,
        "max_colors": 64,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, blood, text, "
            "ui, watermark"
        ),
    },
    # --- 5) Caricatore Esteso: caricatore di proiettili --------------------
    "skill_magazine": {
        "kind": "static",
        "target": "skills/skill_magazine.png",
        "description": (
            "brass bullets magazine clip icon, a curved metal ammunition "
            "magazine with three golden bullets visible on top, dark "
            "outline, perfectly centered, plain simple item icon on empty "
            "background, fantasy pixel art item pickup, readable silhouette, "
            "retro arcade style, crisp pixel art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 113,
        "view": None,
        "max_colors": 48,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, gun, pistol, "
            "text, ui, watermark"
        ),
    },
    # --- 6) Rapidità: stivale alato ------------------------------------------
    "skill_swiftness": {
        "kind": "static",
        "target": "skills/skill_swiftness.png",
        "description": (
            "slim winged boot icon, a small brown leather boot with THIN "
            "small sky blue feather wings spread on the sides and plenty of "
            "empty space around, dark outline, centered but small inside "
            "the frame, fantasy pixel art item pickup, readable silhouette, "
            "retro arcade style, crisp pixel art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 331,
        "view": None,
        "max_colors": 56,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, sandal, text, "
            "ui, watermark"
        ),
    },
    # --- 7) Fortuna del Cacciatore: quadrifoglio -----------------------------
    "skill_luck": {
        "kind": "static",
        "target": "skills/skill_luck.png",
        "description": (
            "lucky four leaf clover icon, glossy bright green shamrock with "
            "a tiny golden sparkle on the top leaf and a dark outline, "
            "perfectly centered, plain simple item icon on empty background, "
            "fantasy pixel art item pickup, readable silhouette, retro "
            "arcade style, crisp pixel art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 131,
        "view": None,
        "max_colors": 40,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, horseshoe, "
            "dice, text, ui, watermark"
        ),
    },
    # --- 8) Rigenerazione: croce medicinale (anchor: item_medikit.png) ------
    "skill_regen": {
        "kind": "static",
        "target": "skills/skill_regen.png",
        "color_image": "/home/z/my-project/ArcadeMaze/godot/assets/sprites/collectibles/item_medikit.png",
        "description": (
            "white medical cross inside a small round pale green potion "
            "flask badge, glowing softly, dark outline, perfectly centered, "
            "plain simple item icon on empty background, fantasy pixel art "
            "item pickup, readable silhouette, retro arcade style, crisp "
            "pixel art, NO text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 137,
        "view": None,
        "max_colors": 48,
        "coverage": (6.0, 60.0),
        "negative_description": (
            "character, face, body, full scene, background, red cross, "
            "syringe, text, ui, watermark"
        ),
    },
    # --- 9) Tile pietra scura del frame modale (TEXTURE opaca) --------------
    "levelup_stone": {
        "kind": "static",
        "target": "skills/levelup_stone_tile.png",
        "description": (
            "seamless dark dungeon stone wall texture panel, rough charcoal "
            "gray brown stone blocks with subtle carved cracks and a faint "
            "warm candle warm tint, flat top-down view, fills the whole "
            "canvas, dark fantasy pixel art texture, no borders, no objects"
        ),
        "size": (256, 256),
        "seed": 139,
        "view": "high top-down",
        "bg_remove": False,
        "palette_reduce": False,
        "outline": None,
        "shading": None,
        "detail": "highly detailed",
        "coverage": (95.0, 100.0),
        "negative_description": (
            "objects, characters, torches, text, ui, watermark, uniform "
            "flat color, blur"
        ),
    },
    # --- 10) Angolo decorato in ottone della card ---------------------------
    "levelup_corner": {
        "kind": "static",
        "target": "skills/levelup_corner.png",
        "description": (
            "ornate corner ornament for a dark stone frame, an L shaped "
            "brass metal corner fitting with rivets and a small decorative "
            "curl, pointing to the top-left, polished golden brass with "
            "dark outline, plain simple ornament on empty background, "
            "fantasy pixel art, retro arcade style, crisp pixel art, NO "
            "text NO UI NO watermark"
        ),
        "size": (64, 64),
        "seed": 149,
        "view": None,
        "max_colors": 56,
        "coverage": (8.0, 60.0),
        "negative_description": (
            "full frame, border on all sides, character, face, background, "
            "scene, text, ui, watermark"
        ),
    },
    # --- 11) Fulmine bianco-oro del LEVEL UP (anim 4f) ----------------------
    "levelup_bolt": {
        "kind": "anim",
        "target": "skills/levelup_bolt_sheet.png",
        "description": (
            "single jagged lightning bolt striking straight down from the "
            "top of the frame to the bottom, white hot core with a warm "
            "golden glow halo and small side branches, seen from the side, "
            "perfectly centered vertical bolt filling the frame, retro "
            "arcade fantasy pixel art, white and warm gold palette on "
            "transparent background"
        ),
        "action": (
            "the lightning bolt flickers and crackles: the zigzag path "
            "reshapes while side branches spark and the golden glow pulses "
            "brighter and dimmer, the bolt stays perfectly centered and "
            "vertical in place, no camera movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 63,
        "anchor": (32, 32),
        "anim_seed": 151,
        "seed": 157,
        "view": "side",
        "negative_description": (
            "horizontal bolt, multiple bolts, cloud, rain, characters, "
            "faces, blue palette, purple palette, text, ui, watermark"
        ),
    },
}

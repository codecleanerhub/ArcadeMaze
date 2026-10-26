#!/usr/bin/env python3
"""Definizioni Task 63 — rigenerazione PixelLab v2 degli sprite pre-V2
superstiti (audit 63: mai toccati dalla v2 del 22-24/10).

63a — GHOST REAPER (Hurry Up!): il fantasma teschio immortale era l'ultimo
      sprite AI pre-V2 visibile in gameplay (141 colori, 11/10). Anim 4f,
      stesso target/nome sheet (SpriteManager id invariato = zero modifiche
      a GhostReaper.gd), alpha ectoplasmatica e variante rossa P2 applicate
      in post-processing (integrate_task63_ghost.py, pattern 61b).
63b — ALTRI SUPERSTITI in-gioco (audit 63): exit_door, dynamite_thrown,
      bonus_speedboots, ui_heart, knight_ally (vedi defs in coda, da
      generare DOPO il push di 63a).

Tutti PNG-first: rollback = ripristinare i .bak-pre-pixellab-v2.
"""
from __future__ import annotations

import os

ENTITIES: dict = {
    # ---------------- 63a — ghost reaper (Hurry Up!) -----------------------
    # Color anchor custom: frame 0 del vecchio sheet con alpha normalizzata
    # a 255 (il vecchio PNG incorpora alpha 184: come reference colore per
    # pixflux darebbe tinte slavate — lo prepara integrate_task63_ghost.py
    # PRIMA del run con --prepare-anchor).
    "ghost_reaper": {
        "kind": "anim",
        "target": "ghost_reaper_sheet.png",
        "color_image": os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "out", "ghost_reaper", "anchor_custom.png"),
        "description": (
            "ghost reaper specter, Slimer style ectoplasm blob ghost with "
            "big grinning skull head, hollow dark eye sockets and two thin "
            "skeletal arms with clawed fingers, translucent glowing green "
            "body, dripping ectoplasm wisps tapering at the bottom like a "
            "classic ghost tail, side view facing right, centered, fantasy "
            "pixel art game monster, readable silhouette, transparent "
            "background"
        ),
        "action": (
            "ghost bobbing and floating forward, skeletal arms waving "
            "slowly, ectoplasm tail wisps undulating, skull grin steady and "
            "centered, silhouette stable, no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
    },
    "ghost_reaper2": {
        # 2° tentativo: la 1° generazione (id ghost_reaper) ha superato la QA
        # numerica ma il VLM comparativo la giudica PIU' FLAT del pre-v2
        # ("teschio smiley, shading base"). Ricetta arricchita: shading
        # avanzato + detail alto + negative anti-flat + seed nuovo.
        "kind": "anim",
        "target": "ghost_reaper_sheet.png",
        "color_image": os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "out", "ghost_reaper", "anchor_custom.png"),
        "description": (
            "ghost reaper specter, Slimer style ectoplasm blob ghost with "
            "big grinning skull head showing detailed cranium cracks and "
            "carved teeth, deep hollow eye sockets with tiny glowing pupils, "
            "two thin skeletal arms with clawed bony fingers, translucent "
            "glowing green body with inner organs faintly visible, dripping "
            "ectoplasm wisps tapering at the bottom like a classic ghost "
            "tail, side view facing right, centered, fantasy pixel art game "
            "monster, readable silhouette, transparent background"
        ),
        "action": (
            "ghost bobbing and floating forward, skeletal arms waving "
            "slowly, ectoplasm tail wisps undulating, skull grin steady and "
            "centered, silhouette stable, no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
        "seed": 21,
        "shading": "highly detailed shading",
        "detail": "highly detailed",
        "negative_description": (
            "flat colors, simple smiley face, cartoon blob, minimal shading, "
            "single flat tone"
        ),
    },
}

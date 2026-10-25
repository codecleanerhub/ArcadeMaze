#!/usr/bin/env python3
"""Definizioni Task 54 — torcia labirinto + portale magico (animati 4 frame).

Nuovi file sheet (i vecchi PNG statici restano come fallback):
  - env/torch_sheet.png   (la torcia era disegnata a primitive in Maze.gd)
  - env/portal_sheet.png  (il portale era disegnato a cerchi in MainGameController)
"""
from __future__ import annotations

ENTITIES: dict = {
    # ---------------- pergamene evento (Task 55) ----------------
    # Rigenerate pixel-art: sono le UNICHE pergamene smooth legacy rimaste;
    # usate sia come pickup nel labirinto sia come icona card bonus.
    "quake_scroll": {
        "kind": "static",
        "target": "parchment/quake_scroll.png",
        "size": (128, 128),
        "description": (
            "ancient parchment scroll rolled and sealed with red wax, cracked stone "
            "tablet symbol of earthquake carved on it, brown aged paper, side view, "
            "centered, fantasy pixel art pickup, readable silhouette, transparent "
            "background"
        ),
    },
    "chasm_scroll": {
        "kind": "static",
        "target": "parchment/chasm_scroll.png",
        "size": (128, 128),
        "description": (
            "ancient parchment scroll rolled with purple magical seal, dark void "
            "portal symbol painted on it, brown aged paper, side view, centered, "
            "fantasy pixel art pickup, readable silhouette, transparent background"
        ),
    },
    "freeze_scroll": {
        "kind": "static",
        "target": "parchment/freeze_scroll.png",
        "size": (128, 128),
        "description": (
            "ancient parchment scroll rolled with icy blue crystal seal, snowflake "
            "and ice shard symbol painted on it, brown aged paper, side view, "
            "centered, fantasy pixel art pickup, readable silhouette, transparent "
            "background"
        ),
    },
    # ---------------- animati Task 54 ----------------
    "maze_torch": {
        "kind": "anim",
        "target": "env/torch_sheet.png",
        "description": (
            "medieval dungeon wall torch, dark wooden handle with iron bracket ring, "
            "bright orange yellow flame on top, side view, centered, fantasy pixel "
            "art, readable silhouette, transparent background"
        ),
        "action": (
            "torch flame flickering and dancing wildly, embers rising, "
            "stable torch handle, no camera movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 60,          # la base della torcia quasi al fondo cella
        "anchor": (32, 60),
        "outline": "single color black outline",
        "shading": "basic shading",
    },
    "magic_portal": {
        "kind": "anim",
        "target": "env/portal_sheet.png",
        "description": (
            "magic portal vortex, swirling ring of purple and cyan energy with "
            "glowing bright core, small sparks around, perfectly round, front "
            "view, centered, fantasy pixel art, transparent background"
        ),
        "action": (
            "portal vortex swirling clockwise, energy spiral rotating, "
            "stable outer ring, pulsing core, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 32,          # oggetto flottante: centrato, non a piedi
        "anchor": (32, 32),
        "outline": "selective outline",
        "shading": "basic shading",
        "bg_remove": True,
    },
}

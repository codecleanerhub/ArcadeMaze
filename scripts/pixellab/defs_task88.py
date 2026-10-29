#!/usr/bin/env python3
"""Definizioni TASK 88 — lama-ruota (blade wheel) per il labirinto.

Asset animato 4 frame (rotazione): ruota circolare di acciaio con denti
triangolari sul bordo, mozzo centrale con rivetti, leggera ruggine. In
gioco i frame ciclano a BLADE_SPIN_FPS (14) per l'effetto di
"scorrimento di ruota", con 2 afterimage di scia dietro il movimento.

Target: godot/assets/sprites/hazards/ (stessa casa di quicksand/trap).
Costo: 5 generazioni (1 base + 4 frame).
"""
from __future__ import annotations

ENTITIES: dict = {
    "blade_wheel": {
        "kind": "anim",
        "target": "hazards/blade_wheel_sheet.png",
        "description": (
            "round metal saw blade wheel with sharp triangular teeth around "
            "the rim, rusty steel disc with a central rivet hub and four bolt "
            "holes, light wear scratches on the metal, perfectly centered "
            "circle filling the frame, front view, retro arcade fantasy "
            "pixel art, clean readable silhouette, steel grey silver palette "
            "with warm rust accents, transparent background"
        ),
        "action": (
            "saw blade spinning in place, teeth rotating clockwise around "
            "the rim, hub steady at the center, circle stable and centered, "
            "no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 63,
        "anchor": (32, 32),
        "anim_seed": 7,
        "seed": 11,
        "view": "side",
        "negative_description": (
            "human, monster, handle, wooden frame, chainsaw body, engine, "
            "blue flames, glowing magic, text"
        ),
    },
}

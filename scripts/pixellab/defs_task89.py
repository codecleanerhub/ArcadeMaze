#!/usr/bin/env python3
"""Definizioni TASK 89 — blocchi di LANCE che escono dal pavimento.

Asset statico 128x128 (cluster di punte di lancia verso l'alto), affettato
localmente in 4 varianti 64x64 (pattern task86_integrate, 0 generazioni
extra). In gioco: punta appena visibile (scale.y ~0.18) -> vibrazione ->
emersione (scale.y -> 1.0) -> 5s fuori -> vibrazione -> rientro.

Target: godot/assets/sprites/hazards/ (stessa casa di quicksand/blade).
Costo: 1 generazione.
"""
from __future__ import annotations

ENTITIES: dict = {
    "spear_tips": {
        "kind": "static",
        "target": "hazards/spear_tips.png",
        "description": (
            "cluster of four medieval spear heads pointing straight up, "
            "sharp steel triangular blades mounted on short wooden shafts, "
            "tips at the top of the image, ground level at the bottom, front "
            "view, filling the frame evenly, retro arcade fantasy pixel art, "
            "clean readable silhouette, steel silver and light brown wood "
            "palette, transparent background"
        ),
        "size": (128, 128),
        "seed": 11,
        "view": "side",
        "max_colors": 48,
        "negative_description": (
            "swords, axes, arrows flying, human hands, skeleton, blood, "
            "glowing magic, single giant spear"
        ),
    },
}

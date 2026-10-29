#!/usr/bin/env python3
"""defs_task72.py — texture roccia UNIFORME per i muri del maze.

TASK 72 (feedback utente): alcuni blocchi muro mostravano "parti piu' scure
arrotondate come se dovessero stare negli angoli ma inserite in maniera
casuale". ROOT CAUSE: la vecchia env/rock_texture.png e' un MASSO unico con
ombra curva; _render_wall_cell ritaglia a caso 1 dei 9 quadrati 64x64 ->
alcuni ritagli contengono archi scuri di bordo in posizioni apparentemente
random (non e' la luce delle lanterne, come sospettava correttamente
l'utente). Fix: texture a faccia di roccia UNIFORME, senza massi, luce
piatta — QUALSIASI ritaglio 64x64 e' pulito.
"""
from __future__ import annotations

import os

ENTITIES: dict = {
    "rock_uniform": {
        "kind": "static",
        "target": "env/rock_texture.png",
        "size": (128, 128),
        "description": (
            "flat seamless rock face texture, uniform even lighting across "
            "the whole surface, dense small stones and fine cracks, subtle "
            "grain, grey monochrome cave wall, top-down view, no large "
            "boulders, no rounded shapes, no shadows, no vignette, no "
            "gradient, uniform brightness everywhere, tileable texture"
        ),
        "seed": 31,
        # ANCHOR: grigio piatto 256x256 (NON la vecchia texture: trascinerebbe
        # il look del masso con ombra curva che stiamo eliminando)
        "color_image": "/tmp/task72_anchor_gray.png",
        "shading": "basic shading",
        "detail": "medium detail",
        "negative_description": (
            "large boulders, rounded rocks, dark curved shadows, corner "
            "shading, vignette, strong light gradient, bright spot, "
            "spotlight, border, frame"
        ),
        # la texture e' sorgente di LUMINANZA: niente bg-removal (full-bleed);
        # riduzione a 16 colori come la vecchia (12 unici) — e' una mappa di
        # luminanza, il tint della palette fa il resto
        "bg_remove": False,
        "palette_reduce": True,
        "max_colors": 16,
        "coverage": (85.0, 100.0),
    },
}

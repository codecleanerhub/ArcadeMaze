#!/usr/bin/env python3
"""defs_task73.py — portale TONDO completo (rigenerazione Task 73).

TASK 73 (feedback utente "e' tagliato il portale"): diagnosi numerica —
NON e' il muro (z-order Task 72 OK): e' l'ASSET portal_sheet.png del
Task 65 che e' un vortice PIATTO (contenuto 60x33, mezzaluna aperta in
alto, "galassia orizzontale"). L'utente lo percepisce come tagliato a
meta' perche' la meta' superiore del cerchio MANCA DALLO SPRITE.

ROOT CAUSE della forma: la ricetta Task 65 uso' color_image = vecchio
sheet piatto -> l'anchor ha trascinato la forma (stessa lezione del
Task 72 sulla texture del masso). FIX: anchor TONDO disegnato ad hoc
(scripts/task73_anchor.py: anello pietra + vortice viola/ciano + core,
238x238, margini 9px) + descrizione/negative che inchiodano il cerchio.
"""
from __future__ import annotations

import os

ENTITIES: dict = {
    "magic_portal": {
        "kind": "anim",
        "target": "env/portal_sheet.png",
        # ANCHOR TONDO generato in repo (deterministico, 0 gen PixelLab):
        # python3 scripts/pixellab/gen_portal_anchor.py
        "color_image": os.path.join(os.path.dirname(__file__), "out",
                                    "magic_portal", "anchor_round.png"),
        "description": (
            "magic portal, PERFECT FULL CIRCLE shape, round stone ring "
            "frame with glowing violet runes, inside the ring a complete "
            "circular vortex of violet and cyan energy spiral filling the "
            "entire circle, bright white glowing core at the center, "
            "small arcane sparks around the rim, front view, perfectly "
            "centered, as tall as it is wide, fantasy pixel art magic "
            "gateway, transparent background"
        ),
        "action": (
            "the energy vortex rotates clockwise inside the steady stone "
            "ring, spiral arms turning around the bright core, sparks "
            "orbiting the rim, stone ring perfectly still and centered, "
            "no color drift, no camera movement, no zoom"
        ),
        "negative_description": (
            "flat galaxy shape, horizontal spiral, wide flat ellipse, "
            "crescent, half circle, cut off, cropped, side view, oval "
            "wider than tall, disc seen at an angle, plain orb, square "
            "shape, minimal shading"
        ),
        "frame_count": 4,
        "frame_px": 64,
        # feet_y=60: contenuto 59px -> y[2..60], centro (31.5, 31), margini 2px
        # (con 58 toccava il bordo alto y[0]; shift +2 applicato a mano sul
        # sheet integrato = identico a rigenerare con 60)
        "feet_y": 60,
        "anchor": (32, 32),    # oggetto flottante: centrato
        "seed": 73,
        "anim_seed": 7,
        "bg_tol": 34,
    },
}

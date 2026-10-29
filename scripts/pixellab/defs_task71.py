#!/usr/bin/env python3
"""Definizioni TASK 71 — rifacimento alleati della statuetta.

Feedback utente: nella card si vedono DUE sprite (statuetta piccola statica
+ alleato grande che si muove) e l'unicorno "sembra un'immagine statica che
si sposta traslando" (pedina che si trascina).

Diagnosi numerica (task71): unicorn_ally_sheet DEGENERATO — frame 0==2 al
bit, frame 1==3==frame 0 traslato 1px (residuo post-allineamento 0.0%).
knight_ally NON degenere (residuo 23-28%) MA rigenerato anch'esso per coerenza
stilistica tra le due varianti della card (richiesta esplicita utente) e perche'
la demo lo riproduceva a 7fps (rigido).

Ricette: nessun color anchor (percorso validato Task 63b knight), shading/detail
'highly detailed' + negative anti-flat/anti-slide, action che FORZA pose
diverse per frame (le gambe si alternano, silhouette cambia). QA con i NUOVI
check pl_qa.check_slide_and_duplicates (duplicati + puro slide).
"""
from __future__ import annotations

ENTITIES: dict = {
    "unicorn_ally": {
        "kind": "anim",
        "target": "unicorn_ally_sheet.png",
        "description": (
            "majestic unicorn ally with pearl white body, flowing pastel "
            "blue mane and tail, golden spiral horn, golden hooves, kind "
            "eye, proud arched neck, full body side view facing right, "
            "mid-trot pose with front legs reaching forward and hind legs "
            "pushing back, all four legs clearly separated and visible, "
            "fantasy pixel art game ally creature, readable silhouette, "
            "transparent background"
        ),
        "action": (
            "unicorn trotting run cycle: diagonal leg pairs alternating, "
            "front legs reaching forward then folding back, hind legs "
            "pushing off then swinging forward, mane and tail flowing and "
            "bouncing with each stride, body slightly stretching and "
            "contracting, hooves lifting off the ground, each frame a "
            "clearly different leg pose, silhouette changes every frame, "
            "no camera movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
        "seed": 11,
        "shading": "highly detailed shading",
        "detail": "highly detailed",
        "view": "side",
        # LEZIONE Task 71: pixflux 'direction' accetta SOLO cardinali
        # (north/east/south/west + diagonali); side-view facing right = east
        # ("right" -> HTTP 422 enum)
        "direction": "east",
        "negative_description": (
            "flat colors, minimal shading, single flat tone, static pose, "
            "sliding translation only, bobbing in place, wooden toy figure, "
            "floating pawn, wings"
        ),
    },
    "knight_ally": {
        # Rigenerazione Task 63b con action rafforzata anti-slide
        "kind": "anim",
        "target": "knight_ally_sheet.png",
        "description": (
            "heroic knight ally in polished silver plate armor with sky "
            "blue tabard and small plumed helmet, raising a gleaming "
            "sword, round shield strapped on the left arm, confident "
            "walking stride, engraved armor details with rivets, side "
            "view facing right, centered, fantasy pixel art game ally "
            "character, readable silhouette, transparent background"
        ),
        "action": (
            "knight marching walk cycle in armor: legs alternating "
            "clearly, one leg stepping forward while the other pushes "
            "back, arms swinging with the stride, tabard and plume "
            "swaying, sword steady, shoulder pauldrons shifting, each "
            "frame a clearly different leg pose, silhouette changes "
            "every frame, no camera movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
        "seed": 11,
        "shading": "highly detailed shading",
        "detail": "highly detailed",
        "view": "side",
        "direction": "east",
        "negative_description": (
            "flat colors, minimal shading, single flat tone, wooden toy "
            "figure, static pose, sliding translation only, bobbing in place"
        ),
    },
}

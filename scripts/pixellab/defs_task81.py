#!/usr/bin/env python3
"""Definizioni TASK 81 — due nuove meccaniche labirinto (richiesta utente):

1) FANTASMI LENZUOLO (bianco/rosso/verde trasparente) che escono dai muri,
   attraversano e si ricompenetrano dal lato opposto. Il bianco e' NATIVO
   (anim 4f); rosso e verde = tint canale in post-processing (pattern 61b
   del recolor, 0 generazioni) — vedi task81_integrate.py.
2) CELLE ZOMBIE nei muri: blocco pietra con finestra inferriata + volto
   zombie dietro le sbarre (statico) + BRACCIA zombie che si protendono
   dal lato della facciata (anim 4f). Le braccia scorrono da DIETRO il
   blocco (slide) quindi il frame dev'essere braccia tese verso destra.

Target: godot/assets/sprites/env/ (stessa casa di torch_sheet.png).
"""
from __future__ import annotations

ENTITIES: dict = {
    # ---------------- 81.1 — fantasma lenzuolo (bianco) -------------------
    # Classico lenzuolo: scialbo con ombre grigio-azzurre, occhi e bocca
    # come fori scuri, senza arti. Il float 4f (bob + orlo ondulato).
    # Trasparenza in-game via modulate.a (0.72 pulsante) come GhostReaper.
    "sheet_ghost": {
        "kind": "anim",
        "target": "env/ghost_sheet_white.png",
        "description": (
            "classic bedsheet ghost, simple rounded shroud of pale white "
            "cloth with a wavy rippling bottom hem, two big dark oval eye "
            "holes and one round open mouth hole below them, no arms no "
            "legs, floating upright, side view facing right, centered, "
            "retro arcade fantasy pixel art, clean readable silhouette, "
            "soft blue-gray shadows, transparent background"
        ),
        "action": (
            "bedsheet ghost floating and bobbing gently in mid air, wavy "
            "bottom hem rippling softly, dark eye holes and mouth hole "
            "steady and centered, silhouette stable, no color drift, "
            "no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
        "seed": 11,
        "negative_description": (
            "skeleton, skull, arms, legs, hat, crown, dripping goo, "
            "glow effects, scary teeth"
        ),
    },
    # ---------------- 81.2 — braccia zombie (escono dalle sbarre) ---------
    # Braccia tese verso destra che ENTRANO dal bordo sinistro del frame:
    # lo slide in-game le fa spuntare da dietro il blocco-finestra.
    "zombie_arms": {
        "kind": "anim",
        "target": "env/zombie_arms_sheet.png",
        "description": (
            "pair of rotting zombie arms reaching to the right with clawed "
            "skeletal hands, torn dark green sleeves and pale decayed green "
            "skin, side view, both arms entering from the left edge of the "
            "frame, vertically centered, fantasy pixel art game hazard, "
            "readable silhouette, transparent background"
        ),
        "action": (
            "zombie arms waving and grasping, clawed fingers flexing open "
            "and closed, arms held steady reaching to the right, no color "
            "drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 56),
        "anim_seed": 7,
        "seed": 23,
        "negative_description": (
            "full zombie body, zombie face, background, walls, blood, "
            "gore, bones scattered"
        ),
    },
    # ---------------- 81.3 — cella zombie (blocco con inferriata) ----------
    # Blocco di pietra PIENO (copre la texture roccia della cella muro:
    # serve OPACO per nascondere le braccia a riposo) con finestra
    # inferriata nella META' DESTRA (facciata che guarda il corridoio) e
    # volto zombie premuto dietro le sbarre. bg_remove=False: niente
    # sfondo da rimuovere (il blocco E' pieno, copre la roccia del muro).
    "zombie_cell": {
        "kind": "static",
        "target": "env/zombie_cell.png",
        "size": (64, 64),
        "description": (
            "square dungeon stone wall block, left half is solid grey "
            "masonry, right half is an open barred prison window flush "
            "against the right edge of the block, four vertical rusty iron "
            "bars from top to bottom, rotting green zombie face with "
            "hollow white eyes pressed behind the bars in the window, side "
            "view, fantasy pixel art, front-lit, flat solid block filling "
            "the whole tile edge to edge"
        ),
        "bg_remove": False,
        "palette_reduce": True,
        "max_colors": 96,
        "coverage": (55.0, 100.0),
        "seed": 47,
        "negative_description": (
            "window in the center, window in the left half, centered "
            "window, transparent center, floating window frame, background "
            "scene, perspective view, wooden door, torch light"
        ),
    },
}

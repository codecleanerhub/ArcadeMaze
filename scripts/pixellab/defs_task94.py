#!/usr/bin/env python3
"""Definizioni TASK 94 — portale infernale, anello runico, lama affilata.

Feedback utente: (1) i portali che si aprono sotto lo sprite del boss alla
morte sembrano procedurali -> asset pixel-art veri; (2) le lame-ruota
sembrano dischi -> devono sembrare LAME affilate; (3) i blocchi blu delle
voragini fuori contesto (gestiti LOCALMENTE con ricolorazione, 0 gen).

1) bossdeath_portal (anim 4f, 128px) — portale infernale che SI APRE nel
   pavimento del dungeon (famiglia hell: DEMON, CULT_HERALD): i 4 frame
   sono gli STADI DI APERTURA (crepa -> fenditura larga -> fossa di lava
   quasi aperta -> pozzo infernale completamente aperto).
2) bossdeath_ring (anim 4f, 128px) — cerchio magico runico rotante sul
   pavimento (famiglie soul/arcane/spectral/bat/crows/mimic): tintato
   per-famiglia via modulate in gioco.
3) blade_sharp (anim 4f, 64px) — lama rotante a 4 bracci affilati
   (shuriken/pinwheel) al posto della ruota-disco: punte triangolari,
   fili lucidi, mozzo piccolo. NON un disco pieno.

Target: godot/assets/sprites/{env,hazards}/.
Costo: 3 anim x 5 = 15 generazioni.
"""
from __future__ import annotations

ENTITIES: dict = {
    # ------------- 94.1 — portale infernale (famiglia hell) ----------------
    # Visto dall'alto: il pavimento di pietra si fende e si apre su un pozzo
    # di lava. I 4 frame = stadi progressivi di apertura: in gioco il frame
    # avanza con l'apertura della voragine (700-1150ms) poi cicla lento.
    "bossdeath_portal": {
        "kind": "anim",
        "target": "env/bossdeath_portal_sheet.png",
        "description": (
            "jagged crack splitting open the dark stone floor of a dungeon, "
            "seen from directly above, top-down view, the fissure widens "
            "into a round pit revealing a glowing orange lava hellhole "
            "below, scorched cracked stone rim with molten veins radiating "
            "outward, embers and small flames licking the rim, perfect "
            "centered round pit filling the frame, retro arcade fantasy "
            "pixel art, dark grey brown dungeon stone palette with bright "
            "orange red lava glow, transparent background"
        ),
        "action": (
            "the ground crack widens frame after frame and the pit opens "
            "up, lava glow intensifying from a thin fissure to a fully open "
            "round hellhole, flames growing on the rim, view perfectly "
            "steady from above, no camera movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 128,
        "feet_y": 127,
        "anchor": (64, 64),
        "anim_seed": 21,
        "seed": 29,
        "view": "high top-down",
        "negative_description": (
            "side view, perspective view, characters, faces, monsters, "
            "walls, bricks, blue colors, water, text, ui"
        ),
    },

    # ------------- 94.2 — anello runico (famiglie magiche) -----------------
    # Cerchio magico runico sul pavimento visto dall'alto, glow neutro
    # chiaro: in gioco viene tintato per-famiglia (verde LICH, viola
    # BEHOLDER, ecc.) via modulate del canvas item.
    "bossdeath_ring": {
        "kind": "anim",
        "target": "env/bossdeath_ring_sheet.png",
        "description": (
            "glowing arcane magic circle engraved on the dark stone floor "
            "of a dungeon, seen from directly above, top-down view, ornate "
            "double ring of runic glyphs with an inner geometric star "
            "pattern, pale cyan white glow with a soft light bloom "
            "spilling on the stone, faint smoke wisps, perfect centered "
            "circle filling the frame, retro arcade fantasy pixel art, "
            "dark grey brown stone with pale glowing runes, transparent "
            "background"
        ),
        "action": (
            "the outer rune ring rotates clockwise while the inner star "
            "pattern rotates counter-clockwise, glyphs lighting up in "
            "sequence around the ring, glow breathing brighter and dimmer, "
            "circle steady and perfectly centered in place, no camera "
            "movement, no color drift"
        ),
        "frame_count": 4,
        "frame_px": 128,
        "feet_y": 127,
        "anchor": (64, 64),
        "anim_seed": 47,
        "seed": 53,
        "view": "high top-down",
        "negative_description": (
            "side view, perspective view, characters, faces, monsters, "
            "fire, lava, orange glow, blue portal, water, text, ui"
        ),
    },

    # ------------- 94.3 — lama affilata (blade trap) -----------------------
    # Sostituisce la ruota-disco: 4 bracci affilati a punta con mozzo
    # centrale piccolo. In gioco i frame ciclano a BLADE_SPIN_FPS.
    "blade_sharp": {
        "kind": "anim",
        "target": "hazards/blade_sharp_sheet.png",
        "description": (
            "four long sharp steel blades radiating from a small central "
            "hub, forming a spinning pinwheel shuriken, seen from directly "
            "above, top-down view, pointed triangular blade arms with "
            "bright polished cutting edges and dark steel bodies, small "
            "riveted round hub, wide gaps of empty space between the "
            "arms, silhouette of a sharp X cross filling the frame, retro "
            "arcade fantasy pixel art, silver steel palette with cool "
            "white edge highlights, transparent background"
        ),
        "action": (
            "the shuriken blades spin in place, the four sharp arms "
            "rotating clockwise around the steady central hub, tips "
            "sweeping the corners of the frame, silhouette stable and "
            "centered, no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 63,
        "anchor": (32, 32),
        "anim_seed": 13,
        "seed": 17,
        "view": "high top-down",
        "negative_description": (
            "round saw disc, circular rim, full solid disc wheel, teeth "
            "around a rim, side view, handle, human, monster, blue glow, "
            "magic, text"
        ),
    },
}

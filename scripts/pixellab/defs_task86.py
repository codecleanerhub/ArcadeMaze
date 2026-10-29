#!/usr/bin/env python3
"""Definizioni TASK 86 — animazioni di morte dei boss: asset pixel-art.

La parte "effetti ambientali + particelle" e' gia' procedurale
(BossDeathSequences.gd, commit d2e8850). Qui generiamo con PixelLab i
5 set-piece visivi che beneficiano dello stile pixel-art coerente col
resto del gioco (pattern dei defs_task63/81):

1) bossdeath_vortex (anim 4f) — vortice di fiamme visto dall'alto per la
   famiglia hell (DEMON, CULT_HERALD): ruota sopra la voragine mentre il
   boss viene risucchiato negli inferi.
2) bossdeath_bat (anim 4f) — pipistrello del vampiro (trasformazione
   finale: vola via a zig-zag prima del lampo).
3) bossdeath_crow (anim 4f) — corvo dello stormo della strega suprema.
4) bossdeath_rubble (statico 128x128) — sassi dello sgretolamento dei
   boss di roccia (GOLEM): affettato localmente in 4 varianti 64x64
   (0 generazioni extra).
5) bossdeath_bones (statico 128x128) — ossa del LICH (varianti 64x64).

Target: godot/assets/sprites/env/ (stessa casa di torch/ghost sheet).
Costo: 3 anim (5 gen l'una) + 2 statici = 17 generazioni.
"""
from __future__ import annotations

ENTITIES: dict = {
    # ---------------- 86.1 — vortice di fiamme (famiglia hell) -------------
    # Visto dall'alto: braccia di fiamma che spiraleggiano in senso orario
    # verso il centro nero. In-game ruota via draw_set_transform sopra la
    # voragine procedurale (layering ibrido).
    "bossdeath_vortex": {
        "kind": "anim",
        "target": "env/bossdeath_vortex_sheet.png",
        "description": (
            "swirling fire vortex whirlpool seen from directly above, top-down "
            "view, spiral arms of orange yellow and red flames rotating "
            "clockwise into a dark black center hole, glowing embers around "
            "the rim, perfect centered circle filling the frame, retro "
            "arcade fantasy pixel art, clean readable shape, warm orange "
            "yellow red palette, transparent background"
        ),
        "action": (
            "fire vortex spinning and swirling clockwise, flame spiral arms "
            "rotating around the dark center hole, embers flickering on the "
            "rim, circle stable and centered, no color drift, "
            "no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 63,
        "anchor": (32, 32),
        "anim_seed": 7,
        "seed": 11,
        "view": "high top-down",
        "negative_description": (
            "side view, perspective view, characters, faces, monsters, "
            "blue flames, green flames, smoke only, water"
        ),
    },

    # ---------------- 86.2 — pipistrello del vampiro ------------------------
    # Corpo piccolo, ali larghe spiegate: il flap 4f deve mantenersi
    # centrato (in-game vola via con zig-zag + scia di scintille al lampo).
    "bossdeath_bat": {
        "kind": "anim",
        "target": "env/bossdeath_bat_sheet.png",
        "description": (
            "small vampire bat flying with both wings spread wide, tiny dark "
            "purple-black furry body, small red glowing eyes, thin membrane "
            "wings with finger bones, pointed ears, side view facing right, "
            "centered, retro arcade fantasy pixel art, clean readable "
            "silhouette, dark purple black red palette, transparent background"
        ),
        "action": (
            "bat flapping wings up and down in flight, wings beating, body "
            "steady and centered, no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 40),
        "anim_seed": 7,
        "seed": 11,
        "negative_description": (
            "vampire man, dracula face, standing pose, huge wings covering "
            "the body, multiple bats, blood, fog"
        ),
    },

    # ---------------- 86.3 — corvo dello stormo della strega ----------------
    "bossdeath_crow": {
        "kind": "anim",
        "target": "env/bossdeath_crow_sheet.png",
        "description": (
            "single crow flying with both wings spread wide, glossy black "
            "feathers with dark violet sheen, strong orange beak, side view "
            "facing right, centered, retro arcade fantasy pixel art, clean "
            "readable silhouette, black dark violet orange palette, "
            "transparent background"
        ),
        "action": (
            "crow flapping wings in flight, wings beating up and down, body "
            "steady and centered, no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 56,
        "anchor": (32, 40),
        "anim_seed": 7,
        "seed": 11,
        "negative_description": (
            "raven standing, multiple birds, bat, skeleton, purple magic "
            "effects, lightning"
        ),
    },

    # ---------------- 86.4 — sassi dello sgretolamento (GOLEM) --------------
    # Statico 128x128: affettato localmente in 4 varianti 64x64 da
    # task86_integrate.py (0 generazioni extra).
    "bossdeath_rubble": {
        "kind": "static",
        "target": "env/bossdeath_rubble.png",
        "description": (
            "scattered pile of grey stone rubble chunks, several angular rock "
            "fragments of different sizes with cracks and facets, grey brown "
            "stone palette, seen from above, filling the frame evenly, retro "
            "arcade fantasy pixel art, clean readable shapes, "
            "transparent background"
        ),
        "size": (128, 128),
        "seed": 11,
        "view": "high top-down",
        "max_colors": 48,
        "negative_description": (
            "boulder, single giant rock, dirt ground, grass, bones, skull, "
            "rubble tower"
        ),
    },

    # ---------------- 86.5 — ossa del LICH -----------------------------------
    "bossdeath_bones": {
        "kind": "static",
        "target": "env/bossdeath_bones.png",
        "description": (
            "small pile of white ivory bones, one skull with dark empty eye "
            "sockets, a few crossed bones and ribs scattered around, pale "
            "bone white grey palette, front view, filling the frame evenly, "
            "retro arcade fantasy pixel art, clean readable shapes, "
            "transparent background"
        ),
        "size": (128, 128),
        "seed": 11,
        "view": "side",
        "max_colors": 48,
        "negative_description": (
            "skeleton standing, full body, zombie, flesh, blood, green "
            "glow, tombstone"
        ),
    },
}

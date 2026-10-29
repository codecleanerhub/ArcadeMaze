#!/usr/bin/env python3
"""Definizioni Task 60 — eliminazione residui procedurali "stonanti"
(audit Task 59, parere 59b approvato dall'utente).

60a — URNE decorative (C): 3 statici che sostituiscono _draw_urn in
      Maze.gd (le 3 palette procedurali 1:1: pietra grigia / bronzo /
      marmo scuro — stesso mapping per hash variante).
60b — PROIETTILI BOSS (B): forme di punta del bestiario.
60c — OVERLAY STATI NEMICI (D): blocco ghiaccio + archetti elettrici
      (simmetrici a effect_fireaura, gia' PNG).

Tutti PNG-first con fallback procedurale nel codice di gioco:
rollback = cancellare il PNG generato.
"""
from __future__ import annotations

ENTITIES: dict = {
    # ---------------- 60a — urne (3 varianti, palette 1:1 col C++) --------
    "urn_stone": {
        "kind": "static",
        "target": "env/urn_stone.png",
        "size": (128, 128),
        "description": (
            "ancient funeral urn carved from weathered grey stone, classical "
            "amphora shape with two curved side handles, cracked surface with "
            "small moss spots, golden relief band with diamond emblem around "
            "the belly, short neck with lid, small square stone pedestal base, "
            "front view, centered, gothic dungeon floor prop, fantasy pixel "
            "art, readable silhouette, transparent background"
        ),
    },
    "urn_bronze": {
        "kind": "static",
        "target": "env/urn_bronze.png",
        "size": (128, 128),
        "description": (
            "ancient funeral urn made of polished bronze copper metal, "
            "classical amphora shape with two curved side handles, green "
            "patina streaks on the shiny surface, dark red painted relief "
            "band with diamond emblem around the belly, short neck with lid, "
            "small square bronze pedestal base, front view, centered, gothic "
            "dungeon floor prop, fantasy pixel art, readable silhouette, "
            "transparent background"
        ),
    },
    "urn_marble": {
        "kind": "static",
        "target": "env/urn_marble.png",
        "size": (128, 128),
        "description": (
            "ancient funeral urn carved from dark purple black marble stone, "
            "classical amphora shape with two curved side handles, deep violet "
            "veins in the polished stone, bright gold leaf relief band with "
            "diamond emblem around the belly, short neck with lid, small "
            "square dark marble pedestal base, front view, centered, gothic "
            "dungeon floor prop, fantasy pixel art, readable silhouette, "
            "transparent background"
        ),
    },
    # ---------------- 60b — proiettili boss di punta (B) ------------------
    # Flagship: DEMONE fireball + DRAGON breath animati (il flicker e'
    # parte dell'identita' visiva; i sheet saranno RIUSATI dal set armi
    # del Drago nel Task 61). Gli altri 4 statici: LICH, GOLEM,
    # WRAITH_LORD, CULT_HERALD. I tipi piccoli/direzionali/blob (eye
    # ray, webshot, claw, fang, goo...) RESTANO procedurali (parere 59b).
    "proj_fireball": {
        "kind": "anim",
        "target": "projectiles/proj_fireball_sheet.png",
        "description": (
            "burning fireball meteor, roaring sphere of bright orange flames "
            "with glowing yellow white hot core, small embers around it, "
            "front view, centered, fantasy pixel art game projectile, "
            "readable silhouette, transparent background"
        ),
        "action": (
            "fireball flames flickering and swirling slowly, embers rising, "
            "ball shape stable and centered, no color drift, no camera "
            "movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 58,
        "anchor": (32, 58),
    },
    "proj_dragon_breath": {
        "kind": "anim",
        "target": "projectiles/proj_dragon_breath_sheet.png",
        "description": (
            "compact dragon breath flame ball, swirling jet of bright orange "
            "fire with white hot center and tiny smoke wisps, front view, "
            "centered, fantasy pixel art game projectile, readable silhouette, "
            "transparent background"
        ),
        "action": (
            "dragon breath flames flickering and twisting, sparks popping, "
            "ball shape stable and centered, no color drift, no camera "
            "movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 58,
        "anchor": (32, 58),
    },
    "proj_necro_bolt": {
        "kind": "static",
        "target": "projectiles/proj_necro_bolt.png",
        "size": (128, 128),
        "description": (
            "floating necromantic energy orb, sickly green glowing sphere with "
            "bright white core and small wispy tendrils below, front view, "
            "centered, fantasy pixel art game projectile, readable silhouette, "
            "transparent background"
        ),
    },
    "proj_boulder": {
        "kind": "static",
        "target": "projectiles/proj_boulder.png",
        "size": (128, 128),
        "description": (
            "huge round granite boulder rock, grey brown rough stone with "
            "dark cracks and chipped edges, front view, centered, fantasy "
            "pixel art game projectile, readable silhouette, transparent "
            "background"
        ),
    },
    "proj_ghost_bolt": {
        "kind": "static",
        "target": "projectiles/proj_ghost_bolt.png",
        "size": (128, 128),
        "description": (
            "glowing cyan spectral bolt, ghostly orb of pale blue green "
            "ectoplasm with bright core and faint wispy tail, front view, "
            "centered, fantasy pixel art game projectile, readable silhouette, "
            "transparent background"
        ),
    },
    "proj_cult_orb": {
        "kind": "static",
        "target": "projectiles/proj_cult_orb.png",
        "size": (128, 128),
        "description": (
            "floating purple magic orb, dark violet sphere with glowing "
            "magenta runes engraved on the surface, bright pink core, small "
            "arcane sparkles around, front view, centered, fantasy pixel art "
            "game projectile, readable silhouette, transparent background"
        ),
    },
    # ---------------- 60c — overlay stati nemici (D) ------------------------
    # Simmetrici a effect_fireaura (PNG): blocco di ghiaccio per i nemici
    # congelati + archetti elettrici per i folgorati.
    # PIVOT iceblock: animate-v3 ha fallito la QA 2 volte (cubetto troppo
    # statico, diff 0.2-1.8%) — integrato STATICo dalla base gia' pagata
    # (integrate_iceblock_static.py -> effect_iceblock.png) con animazione
    # procedurale in codice (sparkles/pulsazione, pattern ibrido Task 57).
    # L'entry anim e' stata RIMOSSA per non ripagare 5 generazioni.
    # La semitrasparenza del ghiaccio e' applicata in codice (modulate),
    # il PNG e' un cristallo pieno perche' l'alpha graduato in
    # generazione e' inaffidabile.
    # Nomi: la convenzione SpriteManager e' {id}_sheet.png a root sprites.
    "effect_shockarc": {
        "kind": "anim",
        "target": "effect_shockarc_sheet.png",
        "description": (
            "ring of four jagged cyan lightning bolts arcing around an "
            "invisible creature, electric arcs with bright yellow white "
            "cores forming a circular crown, front view, centered, fantasy "
            "pixel art status effect overlay, readable silhouette, "
            "transparent background"
        ),
        "action": (
            "lightning bolts flickering and jumping, arcs jitter and swap "
            "positions around the ring, circle shape stable and centered, "
            "no color drift, no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 58,
        "anchor": (32, 58),
    },
}

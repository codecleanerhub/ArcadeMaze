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
}

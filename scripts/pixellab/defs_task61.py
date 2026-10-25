#!/usr/bin/env python3
"""Definizioni Task 61c — PNG PixelLab delle 4 armi elementali prive di
asset riusabile (le altre 9 sono collegate da wire_task61_pickups.py).

Canvas 512x512 = convenzione delle icone reliquia esistenti (in mano +
pickup a terra, normalizzate al 75% dal codice).
"""
from __future__ import annotations

ENTITIES: dict = {
    "throwing_sword": {
        "kind": "static",
        "target": "relics/throwing_sword.png",
        "size": (512, 512),
        "description": (
            "silver throwing sword with long pointed double-edged blade, "
            "small golden crossguard and leather-wrapped grip with round "
            "pommel, diagonal blade pointing up-right, centered, fantasy "
            "pixel art weapon pickup, readable silhouette, transparent "
            "background"
        ),
    },
    "fire_staff": {
        "kind": "static",
        "target": "relics/fire_staff.png",
        "size": (512, 512),
        "description": (
            "gnarled dark wooden wizard staff with glowing ruby crystal "
            "head clawed by gold rings, small orange flames around the "
            "crystal, diagonal staff head pointing up-right, centered, "
            "fantasy pixel art weapon pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "ice_lance": {
        "kind": "static",
        "target": "relics/ice_lance.png",
        "size": (512, 512),
        "description": (
            "long elven ice spear with pale blue frozen crystal blade tip "
            "and silver icy shaft wrapped in leather, frost mist around "
            "the tip, diagonal spearhead pointing up-right, centered, "
            "fantasy pixel art weapon pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "ice_arrow": {
        "kind": "static",
        "target": "relics/ice_arrow.png",
        "size": (512, 512),
        "description": (
            "single elven arrow with pale blue crystal arrowhead, slender "
            "white ash shaft and icy translucent fletching, frost shimmer "
            "on the head, diagonal arrow pointing up-right, centered, "
            "fantasy pixel art weapon pickup, readable silhouette, "
            "transparent background"
        ),
    },
}

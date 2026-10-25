#!/usr/bin/env python3
"""Definizioni Task 53 — collectibles (10) + tesori (5), statici PixelLab v2.

NOTA: le 4 armi pickup (pistol/shotgun/rocket/laser) sono GIA' PixelLab
(canvas 216-238px, palette <=47 colori, EnvironmentArt.gd "PNG PixelLab del
TASK 51") — NON vanno rigenerate.
Ogni item usa color_image = PNG originale (palette ancorata al design
canonico, seed 11) e mantiene la STESSA dimensione canvas del file corrente
(zero modifiche al codice di gioco).
"""
from __future__ import annotations

ENTITIES: dict = {
    # ---------------- collectibles (10) ----------------
    "item_chalice": {
        "kind": "static",
        "target": "collectibles/item_chalice.png",
        "size": (128, 128),
        "description": (
            "ornate golden chalice goblet, holy grail with glowing gems on the rim, "
            "engraved cup stem base, side view, centered, fantasy pixel art item pickup, "
            "readable silhouette, transparent background"
        ),
    },
    "item_dynamite": {
        "kind": "static",
        "target": "collectibles/item_dynamite.png",
        "size": (64, 64),
        "description": (
            "bundle of three red dynamite sticks tied with rope, long fuse on top, "
            "side view, centered, fantasy pixel art item pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "item_hammer": {
        "kind": "static",
        "target": "collectibles/item_hammer.png",
        "size": (128, 128),
        "description": (
            "mighty dwarven war hammer Mjolnir, square stone head with carved runes, "
            "wrapped leather handle, side view diagonal, centered, fantasy pixel art "
            "item pickup, readable silhouette, transparent background"
        ),
    },
    "item_knight_statue": {
        "kind": "static",
        "target": "collectibles/item_knight_statue.png",
        "size": (64, 64),
        "description": (
            "small stone statue of armored knight holding sword upright on pedestal base, "
            "grey weathered marble, front view, centered, fantasy pixel art item pickup, "
            "readable silhouette, transparent background"
        ),
    },
    "item_medikit": {
        "kind": "static",
        "target": "collectibles/item_medikit.png",
        "size": (64, 64),
        "description": (
            "medieval leather healer satchel with red cross emblem and white bandage roll, "
            "side view, centered, fantasy pixel art item pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "item_mine": {
        "kind": "static",
        "target": "collectibles/item_mine.png",
        "size": (128, 128),
        "description": (
            "round black iron naval mine ball with metal spikes, subtle red blinking light, "
            "side view, centered, fantasy pixel art item pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "item_potion": {
        "kind": "static",
        "target": "collectibles/item_potion.png",
        "size": (128, 128),
        "description": (
            "magic ghost potion in round glass flask, bright violet glowing liquid with "
            "bubbles, cork stopper with string, side view, centered, fantasy pixel art "
            "item pickup, readable silhouette, transparent background"
        ),
    },
    "item_scepter": {
        "kind": "static",
        "target": "collectibles/item_scepter.png",
        "size": (128, 128),
        # oggetto intrinsecamente sottile (asta): bbox 73% del canvas ma
        # coverage 7.3% — soglia abbassata (verificato VLM 3/3)
        "coverage": (5.0, 60.0),
        "description": (
            "royal magic scepter, golden rod with glowing blue orb on top and small wings, "
            "vertical diagonal, centered, fantasy pixel art item pickup, readable "
            "silhouette, transparent background"
        ),
    },
    "item_speedboots": {
        "kind": "static",
        "target": "collectibles/item_speedboots.png",
        "size": (128, 128),
        "description": (
            "pair of brown leather boots with small white wings on the sides, magic speed "
            "boots, side view, centered, fantasy pixel art item pickup, readable "
            "silhouette, transparent background"
        ),
    },
    "item_unicorn_statue": {
        "kind": "static",
        "target": "collectibles/item_unicorn_statue.png",
        "size": (64, 64),
        "description": (
            "small white unicorn statue rearing on hind legs, golden spiral horn, stone "
            "pedestal base, side view, centered, fantasy pixel art item pickup, readable "
            "silhouette, transparent background"
        ),
    },
    # ---------------- tesori (5) ----------------
    "treasure_chest": {
        "kind": "static",
        "target": "treasures/treasure_chest.png",
        "size": (128, 128),
        "description": (
            "closed medieval wooden treasure chest with golden metal bands, big lock and "
            "keyhole, slightly open lid with golden glow inside, front view, centered, "
            "fantasy pixel art treasure pickup, readable silhouette, transparent background"
        ),
    },
    "treasure_crown": {
        "kind": "static",
        "target": "treasures/treasure_crown.png",
        "size": (128, 128),
        "description": (
            "golden royal crown with three points, red and blue jewels, small pearls on "
            "the tips, front view, centered, fantasy pixel art treasure pickup, readable "
            "silhouette, transparent background"
        ),
    },
    "treasure_cup": {
        "kind": "static",
        "target": "treasures/treasure_cup.png",
        "size": (128, 128),
        "description": (
            "golden trophy cup with two handles and engraved star, on small round base, "
            "front view, centered, fantasy pixel art treasure pickup, readable silhouette, "
            "transparent background"
        ),
    },
    "treasure_gem": {
        "kind": "static",
        "target": "treasures/treasure_gem.png",
        "size": (128, 128),
        "description": (
            "large cut violet amethyst gemstone, brilliant faceted sparkle, slight inner "
            "glow, front view, centered, fantasy pixel art treasure pickup, readable "
            "silhouette, transparent background"
        ),
    },
    "treasure_gold": {
        "kind": "static",
        "target": "treasures/treasure_gold.png",
        "size": (128, 128),
        "description": (
            "shiny pile of golden coins, few coins stacked and one standing, sparkle "
            "highlights, front view, centered, fantasy pixel art treasure pickup, "
            "readable silhouette, transparent background"
        ),
    },
}

#!/usr/bin/env python3
"""Definizioni TASK 108 — SHOP NEL LABIRINTO + BAMBOLA VOODOO.

Richiesta utente: shop "in stile casa strega/capanna hobbit" nel labirinto,
dentro il quale un mago stile Gandalf/Merlino vende items a punti (cuore,
medikit, bambola voodoo). Tutti gli elementi disegnati con PixelLab.

Asset (tutti STATICI, 1 generazione ciascuno):
  shop_witch_hut    -> collectibles/shop_witch_hut.png   (128x128, facciata)
  item_voodoo       -> collectibles/item_voodoo.png      (128x128, item)
  shop_sign_closed  -> collectibles/shop_sign_closed.png (64x64, cartello;
                       il testo CHIUSO e' reso dal font di gioco sopra il
                       legno, leggibile a qualsiasi scala)
  shop_wizard       -> sprites/shop_wizard.png            (256x256, mago)
  bg_shop           -> backgrounds/bg_shop.png (448x256 -> x3 = 1344x768,
                       interno capanna strega, gestito da gen_task108.py)

Costo totale: 5 generazioni.
"""
from __future__ import annotations

ENTITIES: dict = {
    "shop_witch_hut": {
        "kind": "static",
        "target": "collectibles/shop_witch_hut.png",
        "size": (128, 128),
        "seed": 108,
        "description": (
            "Body: crooked little witch hut shaped like a cozy hobbit "
            "cabin, round wooden door at the bottom center slightly open "
            "with warm light inside, one small round window with glowing "
            "amber light, stone base with dark timber walls. Roof: steep "
            "shaggy wooden shingle roof with moss patches and a small "
            "crooked chimney releasing a tiny smoke puff. Accessories: a "
            "hanging lantern on the left side, two glowing purple magic "
            "crystals near the door step, tiny mushrooms at the base. "
            "Pose: flat front facade view like an arcade shop entrance, "
            "perfectly centered. Palette: warm browns, moss green roof, "
            "glowing amber window, deep purple accents, single color black "
            "outline, retro arcade style, crisp pixel art"
        ),
        "negative_description": (
            "character, creature, person, text, letters, ui, watermark, "
            "side view, top-down map, ground tiles, full scene, interior, "
            "blurry, photorealistic"
        ),
    },
    "item_voodoo": {
        "kind": "static",
        "target": "collectibles/item_voodoo.png",
        "size": (128, 128),
        "seed": 209,
        "description": (
            "Body: small straw voodoo doll with a stitched burlap head, "
            "cross-stitch X eyes, tiny stitched mouth, thin twig arms "
            "crossed on the chest, straw body wrapped with brown thread. "
            "Accessories: three pins with round colored heads stuck into "
            "the body (red, blue, yellow), a tiny purple spell charm tied "
            "to one arm with a thread. Pose: standing upright, perfectly "
            "centered, front view. Palette: tan straw, brown burlap, "
            "bright red blue yellow pin heads, purple charm, single color "
            "black outline, retro arcade style, crisp pixel art"
        ),
        "negative_description": (
            "realistic human doll, human face, gore, blood, scary, text, "
            "ui, watermark, background, full scene, blurry"
        ),
    },
    "shop_sign_closed": {
        "kind": "static",
        "target": "collectibles/shop_sign_closed.png",
        "size": (64, 64),
        "seed": 77,
        "description": (
            "Body: small rectangular wooden sign board hanging from a "
            "rusty nail by two short ropes, weathered brown planks with a "
            "dark wood border, visible wood grain lines, two small rope "
            "holes at the top corners. Pose: front view, perfectly "
            "centered, plain EMPTY board surface. Palette: warm browns, "
            "dark outline, single color black outline, retro arcade "
            "style, crisp pixel art, empty board with no writing"
        ),
        "negative_description": (
            "text, letters, writing, numbers, ui, watermark, character, "
            "background, full scene, open sign, neon"
        ),
    },
    "shop_wizard": {
        "kind": "static",
        "target": "shop_wizard.png",
        "size": (256, 256),
        "seed": 4242,
        "description": (
            "Body: tall old wizard with a very long flowing white beard "
            "reaching his chest, bushy grey eyebrows, wise kind eyes, "
            "gentle smile. Clothing: tall pointed blue-grey hat with a "
            "wide brim and a subtle bent tip, long grey-blue robe with "
            "wide sleeves, brown belt with a golden buckle. Accessories: "
            "a gnarled wooden staff with a small glowing cyan crystal orb "
            "on top held in the right hand, a small leather pouch on the "
            "belt. Pose: standing upright facing front, welcoming open "
            "palm with the left hand. Palette: grey blues, warm beige "
            "skin, pure white beard, glowing cyan orb, golden buckle, "
            "single color black outline, retro arcade style, crisp pixel "
            "art"
        ),
        "negative_description": (
            "young, skeleton, skull, scary, evil, text, ui, watermark, "
            "background, full scene, side view, blurry"
        ),
    },
}

# Lo sfondo interno NON passa da write_static (canvas 336x192 -> x4 NEAREST
# su backgrounds/bg_shop.png): vive qui solo come configurazione prompt.
# NB: la API pixflux rifiuta width > 400 (HTTP 422 verificato): 336x192 e'
# il massimo scala-intera per 1344x768 (x4).
BG_SHOP: dict = {
    "id": "bg_shop",
    "target": "/home/z/my-project/ArcadeMaze/godot/assets/backgrounds/bg_shop.png",
    "gen_size": (336, 192),
    "final_size": (1344, 768),
    "seed": 515,
    "no_background": False,
    "description": (
        "Cozy witch hut interior seen from the front: dark wooden plank "
        "walls, a big stone fireplace with a warm crackling fire on the "
        "left, wooden shelves filled with colorful potion bottles and "
        "glass jars on the right, a small round window with pale "
        "moonlight, bundles of dried herbs hanging from the ceiling "
        "beams, a sturdy wooden counter with lit candles and an open "
        "spell book in the center bottom, warm amber and soft purple "
        "lighting, cozy magical atmosphere, retro arcade pixel art "
        "background, crisp pixel art, no characters, no text"
    ),
    "negative_description": (
        "characters, people, text, letters, ui, watermark, photorealistic, "
        "blurry, outdoors, daylight"
    ),
}

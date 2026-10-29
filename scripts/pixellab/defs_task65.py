#!/usr/bin/env python3
"""Definizioni Task 65 — fix visivi da feedback utente (screenshot + video).

4 rigenerazioni:
  - treasure_ruby   (statico, NUOVO): sostituisce la coppa/trofeo
    (treasure_cup) che l'utente non vuole ("sembra una coppa ma non deve
    vincere nulla, rendi un altro tipo di tesoro, un rubino magari").
    Nuovo file treasures/treasure_ruby.png + enum TRES_CUP -> TRES_RUBY
    (valore 4 invariato: snapshot esistenti restano compatibili).
  - treasure_gem    (statico, RIGEN): la gemma attuale e' TONDA e l'utente
    la legge come "palla blue" che "non si capisce cosa sia". Nuova gemma
    con silhouette classica a punta (corona esagonale + padiglione a
    punta) — inconfondibile pietra preziosa. Anchor = PNG attuale
    (palette blu conservata per varietà' nel set tesori).
  - effect_iceblock (statico, RIGEN): i nemici congelati sembravano
    "quadrati celesti glitch" perche' l'attuale PNG e' la base di una
    animate-v3 FALLITA (cubo isometrico con spesso bordo bianco che
    sembra una selection box). Nuovo cristallo ROTONDO organico senza
    bordo sticker. Anchor = PNG attuale (palette ghiaccio conservata).
  - magic_portal    (anim 4f, RIGEN): l'utente non capiva cosa fosse
    ("e' il portale?"). Il vortice puro si leggeva come sfera/orbo di
    energia. Nuovo design: anello di pietra runica STABILE + vortice
    interno (suggerimento VLM: ring strutturale = "doorway" leggibile).
"""
from __future__ import annotations

import os

ENTITIES: dict = {
    # ---------------- 65c1 — il tesoro coppa diventa un RUBINO -------------
    "treasure_ruby": {
        "kind": "static",
        "target": "treasures/treasure_ruby.png",
        "size": (128, 128),
        "description": (
            "large cut blood red ruby gemstone, classic faceted jewel "
            "silhouette with flat hexagonal crown on top, wide girdle and "
            "pointed pavilion tip at the bottom, brilliant triangular "
            "facets, deep crimson with bright cherry red highlights and "
            "white sparkle glints, slight inner glow, front view, centered, "
            "fantasy pixel art treasure pickup, readable silhouette, "
            "transparent background"
        ),
        "negative_description": (
            "round ball shape, sphere, circular orb, trophy cup, handles, "
            "flat colors, minimal shading"
        ),
        # WAIVER coverage (lezione 61c-l): le gemme grandi riempiono il
        # canvas — la base generata (VLM PASS: silhouette classica a punta,
        # rosso, facet netti) copre 60.6%, appena sopra il default 60.
        # Sovrascritta a 66 solo per questo id, la gemma e' intenzionalmente
        # grande e leggibile (gli altri tesori: 28-52%).
        "coverage": (8.0, 66.0),
    },
    # ---------------- 65c2 — la "palla blue" diventa gemma leggibile --------
    "treasure_gem": {
        "kind": "static",
        "target": "treasures/treasure_gem.png",
        "size": (128, 128),
        # color_image = default (PNG attuale): palette blu ancorata
        "description": (
            "large cut blue sapphire gemstone, classic faceted jewel "
            "silhouette with flat hexagonal crown on top, wide girdle and "
            "pointed pavilion tip at the bottom, brilliant triangular "
            "facets, vivid royal blue with cyan highlights and white "
            "sparkle glints, slight inner glow, front view, centered, "
            "fantasy pixel art treasure pickup, readable silhouette, "
            "transparent background"
        ),
        "negative_description": (
            "round ball shape, sphere, circular orb, flat colors, "
            "minimal shading"
        ),
        "seed": 21,
    },
    # ---------------- 65b — blocco di ghiaccio rotondo leggibile ------------
    # TENTATIVO 2: il tentativo 1 (seed 21, outline default "single color
    # black outline") ha prodotto un cristallo organico OK MA con spesso
    # bordo nero "sticker" — inaccettabile per un overlay che deve fondersi
    # col nemico congelato (VLM FAIL). Ricetta: outline esplicitamente
    # assente + negative anti-bordo + seed nuovo. WAIVER coverage 60.3%
    # (grande massa di ghiaccio, come treasure_ruby).
    "effect_iceblock": {
        "kind": "static",
        "target": "effect_iceblock.png",
        "size": (128, 128),
        # color_image = default (PNG attuale): palette ghiaccio ancorata
        "description": (
            "rounded translucent mass of magical ice, smooth boulder shaped "
            "frozen shell with curved organic edges, jagged frost cracks "
            "and trapped air bubbles inside, pale cyan and white glassy ice "
            "with frosty sparkling surface, semi transparent see through "
            "middle, gentle cold inner glow, front view, centered, fantasy "
            "pixel art status effect overlay, readable silhouette, "
            "transparent background"
        ),
        "negative_description": (
            "outline, border, thick dark edges, square cube, sharp "
            "rectangular edges, sticker look, flat colors"
        ),
        "outline": "lineless",
        "seed": 33,
        "coverage": (8.0, 66.0),
    },
    # ---------------- 65a — portale con anello di pietra + vortice ----------
    "magic_portal": {
        "kind": "anim",
        "target": "env/portal_sheet.png",
        # color_image = default (sheet attuale): palette viola/ciano ancorata
        "description": (
            "ancient magic portal, round carved dark stone ring with "
            "engraved glowing violet runes, swirling vortex of cyan and "
            "violet energy inside the ring spiraling toward a bright "
            "glowing core, small arcane sparks floating around the rim, "
            "front view, centered, fantasy pixel art magic gateway, "
            "readable silhouette, transparent background"
        ),
        "action": (
            "vortex swirling clockwise inside the ring, energy spiral "
            "rotating and pulsing, stone ring steady and perfectly "
            "centered, sparks drifting around the rim, no color drift, "
            "no camera movement"
        ),
        "frame_count": 4,
        "frame_px": 64,
        "feet_y": 32,          # oggetto flottante: centrato, non a piedi
        "anchor": (32, 32),
        "negative_description": (
            "flat colors, square shape, oval ring, no ring, plain orb, "
            "minimal shading"
        ),
        "seed": 21,
    },
}

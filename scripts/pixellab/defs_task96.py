#!/usr/bin/env python3
"""Definizioni TASK 96 — cuore delle vite con sgretolamento progressivo.

Feedback utente: "la barra della vita del player, la togliamo, utilizziamo
i cuori delle vite, li disegniamo se è il caso un pò più grandi (ma poco
più grandi se dobbiamo) e facciamo in modo che il cuore si sgretoli quando
viene colpito il player fino a scomparire e perdere la vita, quindi lo
sgretolamento del cuore sostituisce la barra della vita".

Asset animato 4 frame (24px): i 4 STADI DI SGRETOLOMENTO —
  f0: cuore integro (usato per tutte le vite "piene")
  f1: crepe e piccole schegge mancanti ai bordi
  f2: fratture profonde, parte alta che si sgretola
  f3: quasi distrutto (metà inferiore + frammenti sparsi)
In gioco lo stadio = f(energia/max_energia): ogni 20% di energia persa
avanza di uno stadio; a energia 0 la vita è persa e il cuore sparisce
con un burst di frammenti.

Target: godot/assets/sprites/ui_heart_crumble_sheet.png (stessa casa di
ui_heart.png, che resta come fallback). Color anchor = ui_heart.png
(cuore rosso classico). Costo: 5 generazioni.
"""
from __future__ import annotations

ENTITIES: dict = {
    "ui_heart_crumble": {
        "kind": "anim",
        "target": "ui_heart_crumble_sheet.png",
        "color_image": "/home/z/my-project/ArcadeMaze/godot/assets/sprites/ui_heart.png",
        "description": (
            "pixel art heart, glossy vibrant red heart with a bright "
            "highlight and a dark outline, perfectly centered, plain "
            "simple icon on empty background, retro arcade style, crisp "
            "pixel art, NO text NO UI NO watermark"
        ),
        "action": (
            "the heart cracks and progressively crumbles apart frame by "
            "frame: small cracks and chips appear at the edges, then deep "
            "fractures with fragments breaking off, finally only the "
            "lower half remains with scattered fragments, the heart stays "
            "perfectly centered in place, no movement, no rotation, no "
            "color drift"
        ),
        "frame_count": 4,
        "frame_px": 24,
        "feet_y": 23,
        "anchor": (12, 12),
        "anim_seed": 31,
        "seed": 37,
        "view": None,
        "negative_description": (
            "character, face, legs, arms, full scene, background, blue "
            "heart, green heart, text, ui, watermark"
        ),
    },
}

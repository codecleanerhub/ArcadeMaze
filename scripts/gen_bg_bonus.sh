#!/bin/bash
# Task 23 — Sfondo dedicato SCHERMATA BONUS: fucina/armeria medievale con
# armi di sfondo (spade, mazze, balestre, armature, bastoni magici).
# Stile coerente con gli altri bg del gioco (dark fantasy gotico,
# chiaroscuro, dithering). 1344x768 (widescreen: lezione del Task 16 —
# niente quadrati che il cover-fit trancia).
OUT=/tmp/relic_gen
mkdir -p "$OUT"

if [ -s "$OUT/bg_bonus_raw.png" ]; then
  echo "SKIP bg_bonus_raw (già presente)"
else
  z-ai image -p "Dark fantasy gothic video game background screen, 16-bit inspired detailed digital painting, atmospheric chiaroscuro lighting, dithered textures, dark vignette edges. A vast medieval underground forge armory hall seen from the front, symmetrical composition with large dark empty areas in the center for UI text. Along the dark stone walls: racks of hanging swords, greatswords, maces, war hammers, halberds and loaded crossbows; suits of plate armor standing on wooden stands; tall magic staves leaning in the corners with faintly glowing crystal tips. On the left side a roaring blacksmith forge with glowing orange coals casting warm firelight into deep brown-black shadows, golden highlights, dark crimson accents, sparks drifting in the air. Empty dark stone floor in the foreground. No people, no characters, no text, no watermark." -o "$OUT/bg_bonus_raw.png" -s 1344x768 && echo "OK bg_bonus_raw" || echo "FAIL bg_bonus_raw"
fi
ls -la "$OUT"

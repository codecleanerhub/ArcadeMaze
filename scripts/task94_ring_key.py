#!/usr/bin/env python3
"""Task 94 — post-lavoro sheet anello runico: keying di luminanza.

L'anello PixelLab è un tile pieno (pietra scura + cerchio incandescente).
In gioco viene TINTATO per-famiglia via modulate: se lasciassimo la
pietra, tintandola diventerrebbe verde/viola innaturale. Rimuoviamo la
pietra scura (lum < 72) con rampa morbida 72-112: resta solo il cerchio
glow + alone. Il portale infernale invece resta tile pieno (la pietra
crepata È il pavimento che si apre).
"""
from PIL import Image

SRC = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/env/bossdeath_ring_sheet.png"

im = Image.open(SRC).convert("RGBA")
out = Image.new("RGBA", im.size, (0, 0, 0, 0))
sp, op = im.load(), out.load()
for y in range(im.height):
    for x in range(im.width):
        r, g, b, a = sp[x, y]
        if a == 0:
            continue
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        # rampa: 0 sotto 72, 255 sopra 112
        na = int(a * max(0.0, min(1.0, (lum - 72.0) / 40.0)))
        if na > 0:
            op[x, y] = (r, g, b, na)
out.save(SRC)
print("ring sheet keyato:", SRC)

# sanity: opacita' residua per frame
for i in range(4):
    f = out.crop((i * 128, 0, (i + 1) * 128, 128))
    op_n = sum(1 for p in f.getdata() if p[3] > 64)
    print(f"  frame {i}: pixel glow {op_n / 16384 * 100:.1f}%")

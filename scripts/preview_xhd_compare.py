## preview_xhd_compare.py - Confronto visivo: look attuale (NEAREST 3x) vs
## varianti XHD 4x, tutti mostrati alla stessa dimensione a schermo (192px,
## la dimensione del personaggio frontale nella ruota di selezione).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from upscale_xhd_lib import upscale_frame_4x

SPR = "/home/z/my-project/ArcadeMaze/godot/assets/sprites"
OUT = "/home/z/my-project/download/xhd_preview_compare.png"

CELL = 192          # on-screen size (wheel front char)
BG = (34, 34, 42, 255)
LABEL_H = 34

SUBJECTS = [
    ("player1_sheet.png", 0, "PLAYER - Hero"),
    ("boss_031_sheet.png", 0, "BOSS - Stone Golem"),
    ("boss_030_sheet.png", 0, "BOSS - Kraken"),
    ("char_dragon_sheet.png", 0, "PLAYER - Dragon"),
]

COLS = ["ATTUALE (nearest 3x)", "XHD snap (proposta)", "XHD soft"]
N = len(SUBJECTS)

font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
font = ImageFont.truetype(font_path, 17)

W = CELL * 3 + 40 * 4
H = LABEL_H + N * (CELL + 30) + 10
canvas = Image.new("RGBA", (W, H), BG)
draw = ImageDraw.Draw(canvas)


def get_frame(fname, idx):
    im = Image.open(os.path.join(SPR, fname)).convert("RGBA")
    if im.width == 4 * im.height:
        return im.crop((idx * 64, 0, (idx + 1) * 64, 64))
    return im


def soft_4x(frame):
    """bicubic 4x senza snap (variante morbida)."""
    big = frame.resize((256, 256), Image.BICUBIC)
    a = np.array(big).astype(np.float32)
    alpha = a[:, :, 3]
    x = np.clip((alpha - 96.0) / 64.0, 0.0, 1.0)
    a[:, :, 3] = x * x * (3 - 2 * x) * 255.0
    return Image.fromarray(a.astype(np.uint8), "RGBA")


for c, label in enumerate(COLS):
    x0 = 40 + c * (CELL + 40)
    draw.text((x0, 8), label, font=font, fill=(240, 220, 140, 255))

for r, (fname, idx, subj) in enumerate(SUBJECTS):
    frame = get_frame(fname, idx)
    y0 = LABEL_H + 10 + r * (CELL + 30)
    draw.text((6, y0 + CELL // 2 - 10), subj.replace(" - ", "\n"), font=font,
              fill=(150, 160, 180, 255))

    # A: look attuale = nearest 3x
    cur = frame.resize((CELL, CELL), Image.NEAREST)
    # B: XHD snap 4x -> mostrato a 192px (downscale, come farà la GPU con LINEAR)
    xhd_snap = upscale_frame_4x(frame).resize((CELL, CELL), Image.LANCZOS)
    # C: XHD soft
    xhd_soft = soft_4x(frame).resize((CELL, CELL), Image.LANCZOS)

    for c, img in enumerate([cur, xhd_snap, xhd_soft]):
        x0 = 40 + c * (CELL + 40)
        # ombra a terra per realism
        canvas.alpha_composite(img, (x0, y0))

canvas.convert("RGB").save(OUT, optimize=True)
print("saved", OUT, canvas.size)

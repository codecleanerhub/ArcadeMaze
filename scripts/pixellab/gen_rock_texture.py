#!/usr/bin/env python3
"""Task 57: genera la texture roccia PixelLab per i muri del labirinto.

ATTENZIONE: e' una TEXTURE (opaca, tileable-ish), non uno sprite — niente
bg removal, niente QA sprite. Il tiling e' gia' gestito dal renderer con
crop 64px deterministici per cella.
La texture viene usata come SORGENTE DI LUMINANZA (normalizzata 2-98
percentili) e tintata con le 8 palette esistenti in Maze.gd.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pl_api

OUT = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/env/rock_texture.png"
DESC = (
    "seamless dungeon cave rock wall texture, rough porous gray stone with "
    "natural cracks and deep crevices, chunky mineral grain, dark fantasy "
    "pixel art texture, top-down flat view, fills the whole canvas, no "
    "borders, no objects"
)

if os.path.isfile(OUT):
    print("texture esistente — la sovrascrivo con backup manuale .bak-task57")
    import shutil
    shutil.copy2(OUT, OUT + ".bak-task57")

imgs = pl_api.create_image_pixflux(
    description=DESC,
    width=256, height=256,
    color_image_path=None,   # nessun anchor: texture pura
    seed=11,
    no_background=False,     # TEXTURE: serve opaca!
    outline=None, shading=None, detail="highly detailed",
    view="high top-down",
    negative_description="objects, characters, torches, bricks pattern, "
                         "uniform flat color, blur",
    raw_dump_path=os.path.join(os.path.dirname(__file__), "out",
                               "rock_texture", "raw_pixflux.json"),
)
pl_api.save_b64_image(imgs[0], "/tmp/rock_raw.png")

# normalizza luminanza (percentili 2-98) e salva 128x128 grayscale-info
from PIL import Image, ImageOps
img = Image.open("/tmp/rock_raw.png").convert("RGB")
img = img.resize((128, 128), Image.NEAREST)
gray = ImageOps.grayscale(img)
lo, hi = gray.getextrema()
if hi - lo < 24:  # fallback: istogramma piatto
    lo, hi = 30, 220
# stretch dei percentili via point
hist_lo = gray.point(lambda v: v if v >= lo else lo)
hist_hi = hist_lo.point(lambda v: v if v <= hi else hi)
norm = ImageOps.autocontrast(hist_hi, cutoff=1)
norm_rgb = Image.merge("RGB", (norm, norm, norm))
norm_rgb.save(OUT, "PNG")
px = list(norm.getdata())
print(f"texture salvata: {OUT} 128x128, luminanza {min(px)}-{max(px)} "
      f"(stretch {lo}-{hi})")

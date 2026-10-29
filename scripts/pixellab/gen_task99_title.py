#!/usr/bin/env python3
"""gen_task99_title.py — scritta "LEVEL UP!" in pixel-font dorato (TASK 99).

Pattern task76 (parole degli achievemтnt): chiamata pixflux DIRETTA con
aspect largo (400x150, il run_static e' fissato 256x256), poi bg-clean e
crop-to-content. Nessun QA sprite standard (e' una scritta: coverage alta,
niente silhouette): check solo su larghezza contenuto e palette.

Output: godot/assets/sprites/skills/levelup_title.png (crop del contenuto).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pl_api
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "out", "levelup_title")
OUT = "/home/z/my-project/ArcadeMaze/godot/assets/sprites/skills/levelup_title.png"
os.makedirs(OUT_DIR, exist_ok=True)

DESC = (
    "the words LEVEL UP! written in big bold golden pixel font letters with "
    "a beveled metallic shine and a dark outline, warm gold and pale yellow "
    "palette, perfectly centered horizontal text on empty background, retro "
    "arcade fantasy pixel art, crisp pixel art, no other objects"
)
NEG = (
    "characters, monsters, weapons, lightning, background scenery, blue "
    "text, red text, blurry, watermark"
)

imgs = pl_api.create_image_pixflux(
    description=DESC,
    width=400, height=148,
    color_image_path=None,
    seed=163,
    no_background=True,
    outline="single color black outline",
    shading="basic shading",
    detail="medium detail",
    view=None,
    direction=None,
    negative_description=NEG,
    raw_dump_path=os.path.join(OUT_DIR, "raw_pixflux.json"),
)
pl_api.save_b64_image(imgs[0], os.path.join(OUT_DIR, "base.png"))

img = Image.open(os.path.join(OUT_DIR, "base.png")).convert("RGBA")


def _remove_bg(im):
    # riusa la pulizia standard (flood-fill dai bordi, tol=26)
    import pl_integrate
    return pl_integrate.remove_solid_background(im, tol=26)


img = _remove_bg(img)

# crop-to-content con margine 4px
bbox = img.getbbox()
if bbox is not None:
    from PIL import ImageOps
    img = img.crop(bbox)
    img = ImageOps.expand(img, border=4, fill=(0, 0, 0, 0))

img.save(OUT, "PNG")
px = [p for p in img.getdata() if p[3] > 0]
print(f"scritta salvata: {OUT} {img.size[0]}x{img.size[1]}, "
      f"{len(px)} px opachi")
if img.size[0] < 120 or img.size[1] < 24:
    print("ATTENZIONE: contenuto troppo piccolo, rigenerare con altro seed")
    sys.exit(1)

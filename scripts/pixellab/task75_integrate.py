#!/usr/bin/env python3
"""task75_integrate.py — TASK 75: integrazione dei frame generati.

- WALK base (mage, orc, golem, dragon, vampire):
    SD  char_X_sheet.png   256x64  (frame 64px, piedi a 56) + mirror legacy
    XHD xhd/char_X_xhd_sheet.png 1024x256 (frame 256px NATIVI, piedi a 224)
- WALK armored (player1, player2, orc, golem, dragon, vampire):
    SOLO XHD xhd/<id>_armored_xhd_sheet.png (il loader armored e' XHD-only)
- STATUA unicorno: r4 pietrificato -> item_unicorn_statue.png 64x64
  (pipeline Task 74: bg removal, rampa pietra se sat alta, muschio base)

I meta _meta.json dei player NON vengono toccati (il gioco non li legge:
Player.gd hardcodda il ciclo, SelectPlayer/card caricano i PNG direttamente).
I .bak-pre-pixellab-v2 sono gitignorati (*.bak-*).

Uso: python3 task75_integrate.py [--dry]
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from PIL import Image

import pl_integrate
import pl_qa
import task74_petrify  # saturation_stats / stone_remap / RAMP riutilizzati

OUT = os.path.join(HERE, "out", "task75")
GODOT_SPRITES = pl_integrate.GODOT_SPRITES

# entita' -> (target SD relativo | None, target XHD relativo | None)
WALKS: dict = {
    "walk_mage":    ("char_mage_sheet.png",   "xhd/char_mage_xhd_sheet.png"),
    "walk_orc":     ("char_orc_sheet.png",    "xhd/char_orc_xhd_sheet.png"),
    "walk_golem":   ("char_golem_sheet.png",  "xhd/char_golem_xhd_sheet.png"),
    "walk_dragon":  ("char_dragon_sheet.png", "xhd/char_dragon_xhd_sheet.png"),
    "walk_vampire": ("char_vampire_sheet.png", "xhd/char_vampire_xhd_sheet.png"),
    "arm_player1":  (None, "xhd/player1_armored_xhd_sheet.png"),
    "arm_player2":  (None, "xhd/player2_armored_xhd_sheet.png"),
    "arm_orc":      (None, "xhd/char_orc_armored_xhd_sheet.png"),
    "arm_golem":    (None, "xhd/char_golem_armored_xhd_sheet.png"),
    "arm_dragon":   (None, "xhd/char_dragon_armored_xhd_sheet.png"),
    "arm_vampire":  (None, "xhd/char_vampire_armored_xhd_sheet.png"),
}


def clean_frame(img: Image.Image) -> Image.Image:
    """Se lo sfondo e' solido -> flood removal; se gia' trasparente ->
    solo binarizzazione alpha (il flood su trasparente mangerebbe i
    contorni neri: bg stimato (0,0,0) dagli angoli trasparenti)."""
    a = np.array(img.convert("RGBA"))
    corners = [int(a[0, 0, 3]), int(a[0, -1, 3]), int(a[-1, 0, 3]), int(a[-1, -1, 3])]
    if min(corners) > 200:
        return pl_integrate.remove_solid_background(img, tol=34)
    a[:, :, 3] = np.where(a[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    return Image.fromarray(a)


def feet_align(frame: Image.Image, frame_px: int, feet_y: int) -> Image.Image:
    """Ultima riga opaca -> feet_y (shift verticale, pattern write_anim_sheet)."""
    fr = frame.convert("RGBA")
    if fr.size != (frame_px, frame_px):
        fr = fr.resize((frame_px, frame_px), Image.NEAREST)
    px = fr.load()
    last_opaque = 0
    for y in range(frame_px - 1, -1, -1):
        if any(px[x, y][3] > 0 for x in range(0, frame_px, 2)):
            last_opaque = y
            break
    shift = feet_y - last_opaque
    cell = Image.new("RGBA", (frame_px, frame_px), (0, 0, 0, 0))
    cell.paste(fr, (0, shift), fr)
    return cell


def compose_sheet(frames: list[Image.Image], frame_px: int, feet_y: int) -> Image.Image:
    sheet = Image.new("RGBA", (4 * frame_px, frame_px), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(feet_align(f, frame_px, feet_y), (i * frame_px, 0))
    return sheet


def n_colors(img: Image.Image) -> int:
    a = np.array(img.convert("RGBA"))
    op = a[:, :, 3] > 0
    return int(len({tuple(p) for p in a[op][:, :3]}))


def integrate_walk(entity: str, dry: bool) -> bool:
    sd_rel, xhd_rel = WALKS[entity]
    d = os.path.join(OUT, entity)
    ref = Image.open(os.path.join(d, "first.png")).convert("RGBA")
    frames = [clean_frame(Image.open(os.path.join(d, "raw", f"r{i}.png")))
              for i in range(1, 5)]

    errors = pl_qa.qa_anim_frames(frames, ref=ref)
    ok = pl_qa.report(entity, errors)
    print(f"    colori unici per frame: "
          f"{[n_colors(f) for f in frames]} (256px)")

    # anteprima sheet (sempre, anche dry)
    sd_sheet = compose_sheet(frames, 64, 56)
    xhd_sheet = compose_sheet(frames, 256, 224)
    prev = Image.new("RGBA", (256 * 2 + 8, 256), (40, 40, 48, 255))
    prev.alpha_composite(sd_sheet.resize((256, 64), Image.NEAREST), (0, 96))
    prev.alpha_composite(xhd_sheet.resize((256, 64), Image.LANCZOS), (264, 96))
    prev.save(os.path.join(d, "preview_sheets.png"))

    if not ok:
        print(f"    [SKIP] {entity}: QA fallita, NON integrato")
        return False
    if dry:
        print(f"    [dry] {entity}: QA ok, integrazione saltata")
        return True

    if sd_rel is not None:
        sd_path = os.path.join(GODOT_SPRITES, sd_rel)
        pl_integrate.backup_original(sd_path)
        sd_sheet.save(sd_path, "PNG")
        pl_integrate._sync_mirror(sd_rel, sd_path)
        print(f"    SD  -> {sd_path}")
    xhd_path = os.path.join(GODOT_SPRITES, xhd_rel)
    pl_integrate.backup_original(xhd_path)
    xhd_sheet.save(xhd_path, "PNG")
    print(f"    XHD -> {xhd_path}")
    return True


def integrate_unicorn_statue(dry: bool) -> bool:
    d = os.path.join(OUT, "unicorn_statue")
    # r4 = il piu' pietrificato (VLM: r4 "remains monochrome stone")
    img = Image.open(os.path.join(d, "raw", "r4.png")).convert("RGBA")
    img = clean_frame(img)
    mean_sat, max_sat = task74_petrify.saturation_stats(img)
    print(f"    r4 post-clean: sat media {mean_sat:.1f}, max {max_sat:.1f}")
    if mean_sat > 18.0 or max_sat > 90.0:
        print("    -> remap in rampa pietra (fallback deterministico)")
        img = task74_petrify.stone_remap(img)
        mean_sat, max_sat = task74_petrify.saturation_stats(img)
        print(f"    post-remap: sat media {mean_sat:.1f}, max {max_sat:.1f}")

    errors = pl_qa.qa_static(img.resize((64, 64), Image.NEAREST))
    pl_qa.report("unicorn_statue", errors)

    a = np.array(img)
    ys, xs = np.nonzero(a[:, :, 3] > 10)
    print(f"    contenuto 256: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}] "
          f"({xs.max()-xs.min()+1}x{ys.max()-ys.min()+1})")

    if dry:
        img.resize((64, 64), Image.NEAREST).save(os.path.join(d, "preview.png"))
        print("    [dry] integrazione saltata")
        return True

    final = pl_integrate.write_static("collectibles/item_unicorn_statue.png",
                                      img, (64, 64))
    # muschio deterministico alla base (pattern task74_integrate, seed 75)
    im = Image.open(final).convert("RGBA")
    a = np.array(im)
    op = a[:, :, 3] > 10
    last_rows = np.nonzero(op.any(axis=1))[0]
    y_feet = int(last_rows.max())
    rng = np.random.default_rng(75)
    moss = (74, 96, 66)
    placed = 0
    for _ in range(40):
        if placed >= 8:
            break
        x = int(rng.integers(18, 46))
        y = int(y_feet - rng.integers(0, 5))
        if 0 <= y < 64 and a[y, x, 3] > 10:
            lum = 0.299 * a[y, x, 0] + 0.587 * a[y, x, 1] + 0.114 * a[y, x, 2]
            if 70 < lum < 190:
                a[y, x, 0], a[y, x, 1], a[y, x, 2] = moss
                a[y, x, 3] = 255
                placed += 1
    Image.fromarray(a).save(final)
    pl_integrate._sync_mirror("collectibles/item_unicorn_statue.png", final)
    print(f"    STATUA -> {final} (muschio {placed} px)")
    return True


def main() -> None:
    dry = "--dry" in sys.argv
    print("=== STATUA UNICORNO ===")
    integrate_unicorn_statue(dry)
    print("=== WALK ===")
    for entity in WALKS:
        print(f"-- {entity}")
        integrate_walk(entity, dry)


if __name__ == "__main__":
    main()

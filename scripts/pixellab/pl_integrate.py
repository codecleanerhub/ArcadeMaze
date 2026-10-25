#!/usr/bin/env python3
"""Integrazione asset PixelLab v2 nel progetto Godot (§8.2 passo 5).

- backup dell'originale come .bak-pre-pixellab-v2 (accanto al file)
- scrittura PNG finale alla dimensione target (item statici)
- composizione sheet 256x64 (4 frame da 64x64) + meta.json per gli animati
- sync mirror legacy ArcadeMaze/assets/sprites/ se il percorso esiste
"""
from __future__ import annotations

import json
import os
import shutil
from PIL import Image

GODOT_SPRITES = "/home/z/my-project/ArcadeMaze/godot/assets/sprites"
LEGACY_MIRROR = "/home/z/my-project/ArcadeMaze/assets/sprites"
BAK_SUFFIX = ".bak-pre-pixellab-v2"


def _abs(rel: str) -> str:
    if rel.startswith("/"):
        return rel
    return os.path.join(GODOT_SPRITES, rel)


def backup_original(target_path: str) -> str | None:
    """Backup .bak-pre-pixellab-v2 (una sola volta)."""
    if not os.path.isfile(target_path):
        return None
    bak = target_path + BAK_SUFFIX
    if not os.path.isfile(bak):
        shutil.copy2(target_path, bak)
    return bak


def write_static(target_rel: str, img: Image.Image, target_size: tuple[int, int] | None = None) -> str:
    """Scrive uno statico: backup + resize LANCZOS al target + PNG RGBA."""
    path = _abs(target_rel)
    backup_original(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = img.convert("RGBA")
    if target_size and out.size != target_size:
        out = out.resize(target_size, Image.LANCZOS)
    out.save(path, "PNG")
    _sync_mirror(target_rel, path)
    return path


def write_anim_sheet(target_rel: str, frames: list[Image.Image],
                     frame_px: int = 64, feet_y: int = 56,
                     anchor: tuple[int, int] = (32, 56),
                     columns: int = 4, rows: int = 1) -> str:
    """Composita lo sheet (columns*frame_px x rows*frame_px), piedi a feet_y.

    Ogni frame viene scalato a frame_px e allineato col fondo piedi a feet_y
    (shift verticale uniforme, §8.2 passo 5).
    """
    assert frames, "write_anim_sheet: nessun frame"
    path = _abs(target_rel)
    backup_original(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet = Image.new("RGBA", (columns * frame_px, rows * frame_px), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        if i >= columns * rows:
            break
        fr = f.convert("RGBA")
        if fr.size != (frame_px, frame_px):
            fr = fr.resize((frame_px, frame_px), Image.LANCZOS)
        # allinea piedi: ultima riga opaca -> feet_y
        px = fr.load()
        last_opaque = 0
        for y in range(frame_px - 1, -1, -1):
            if any(px[x, y][3] > 0 for x in range(0, frame_px, 2)):
                last_opaque = y
                break
        shift = feet_y - last_opaque
        cell = Image.new("RGBA", (frame_px, frame_px), (0, 0, 0, 0))
        cell.paste(fr, (0, shift), fr)
        cx = (i % columns) * frame_px
        cy = (i // columns) * frame_px
        sheet.paste(cell, (cx, cy), cell)
    sheet.save(path, "PNG")
    # meta.json standard del gioco
    meta = {"columns": columns, "rows": rows,
            "anchor": {"x": anchor[0], "y": anchor[1]}}
    meta_path = os.path.splitext(path)[0] + "_meta.json"
    backup_original(meta_path)
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    _sync_mirror(target_rel, path)
    _sync_mirror(os.path.relpath(meta_path, GODOT_SPRITES), meta_path)
    return path


def _sync_mirror(rel: str, abs_path: str) -> None:
    """Sync mirror legacy ArcadeMaze/assets/sprites/ SOLO se la cartella esiste."""
    mirror = os.path.join(LEGACY_MIRROR, rel)
    if os.path.isdir(os.path.dirname(mirror)):
        os.makedirs(os.path.dirname(mirror), exist_ok=True)
        shutil.copy2(abs_path, mirror)


def quantize_to_palette(img: Image.Image, ref: Image.Image,
                        max_palette: int = 96) -> Image.Image:
    """Quantizza al nearest color della palette del reference (RGB + luminanza).

    Se il reference ha troppi colori (art legacy smooth), la palette viene
    prima ridotta con quantize PIL ai colori dominanti.
    """
    src = img.convert("RGBA")
    ref_rgba = ref.convert("RGBA")
    ref_cols = sorted({(p[0], p[1], p[2]) for p in ref_rgba.getdata() if p[3] > 0})
    if len(ref_cols) > max_palette:
        pal_img = ref_rgba.convert("RGB").quantize(colors=max_palette, method=Image.MEDIANCUT)
        ref_cols = sorted({tuple(c) for c in pal_img.getdata()})
    lut = ref_cols
    out = src.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            best, bd = None, 1 << 30
            for (rr, gg, bb) in lut:
                d = (r - rr) * (r - rr) * 2 + (g - gg) * (g - gg) * 4 + (b - bb) * (b - bb) * 2
                if d < bd:
                    bd, best = d, (rr, gg, bb)
            px[x, y] = (best[0], best[1], best[2], 255 if a > 128 else 0)
    return out

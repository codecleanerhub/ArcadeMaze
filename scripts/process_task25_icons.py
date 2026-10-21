#!/usr/bin/env python3
"""Task 25 — Processing icone rigenerate (chroma-key CIANO, famiglia opposta).

LEZIONE Task 25 (root cause dei manici spezzati): i manici con cuoio/cuoio
rosso (crimson) passano la GUARDIA DELLA FAMIGLIA MAGENTA (r > g+25 AND
b > g-8) e il flood li mangia -> manici frammentati in 2-20 pezzi.
Soluzione: generare su sfondo CIANO e processare con cyan=True — acciaio,
legno, oro, verde e crimson NON passano mai la guardia ciano
(b > r+25 AND g > r+10).

Riusa le funzioni di process_relic_icons.py (flood locale + frangia +
despill) e replica trim/margine/crop/resize con lato parametrico:
  * 5 reliquie frammentate -> 512px in assets/sprites/relics/
  * item_hammer (Mjolnir pickup) -> 128px in assets/sprites/collectibles/
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

SCRIPTS = Path("/home/z/my-project/ArcadeMaze/scripts")
sys.path.insert(0, str(SCRIPTS))
import process_relic_icons as pri  # noqa: E402

RAW = Path("/tmp/relic_gen25")
RELICS_OUT = Path("/home/z/my-project/ArcadeMaze/godot/assets/sprites/relics")
HAMMER_OUT = Path("/home/z/my-project/ArcadeMaze/godot/assets/sprites/collectibles")


def _components8(mask: np.ndarray):
    """Componenti connesse 8-conn (BFS). Ritorna (labels, [(area, id), ...])."""
    from collections import deque
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    comps = []
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                cid = len(comps) + 1
                q = deque([(y, x)])
                lab[y, x] = cid
                area = 0
                while q:
                    cy, cx = q.popleft()
                    area += 1
                    for ny, nx in [(cy-1,cx),(cy+1,cx),(cy,cx-1),(cy,cx+1),
                                   (cy-1,cx-1),(cy-1,cx+1),(cy+1,cx-1),(cy+1,cx+1)]:
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cid
                            q.append((ny, nx))
                comps.append((area, cid))
    return lab, comps


def _drop_background_blobs(alpha: np.ndarray) -> np.ndarray:
    """TASK 25: la vignette scura negli angoli del PNG AI (teal scuro che non
    passa la guardia ciano) sopravvive alla chiave come blob opaco staccato
    dall'oggetto. Regola: tiene il componente principale + i componenti che
    stanno ENTRO 24px di distanza reale dai suoi pixel (dilatazione
    morfologica: le armi diagonali hanno bbox enormi e il test bbox-only
    tengono i blob d'angolo); scarta il resto (blob di vignette, polvere)."""
    from PIL import ImageFilter
    opaque = alpha > 16
    if not opaque.any():
        return alpha
    lab, comps = _components8(opaque)
    if len(comps) <= 1:
        return alpha
    comps_sorted = sorted(comps, reverse=True)
    main_id = comps_sorted[0][1]
    # dilatazione 24px (MaxFilter 49) del componente principale
    main_img = Image.fromarray((lab == main_id).astype(np.uint8) * 255, mode="L")
    dilated = np.array(main_img.filter(ImageFilter.MaxFilter(49))) > 0
    keep_ids = {main_id}
    for ar, cid in comps_sorted[1:]:
        if (dilated & (lab == cid)).any():
            keep_ids.add(cid)
    drop = opaque & ~np.isin(lab, list(keep_ids))
    if drop.any():
        alpha = alpha.copy()
        alpha[drop] = 0
    return alpha

JOBS = [
        # (id_raw, id_out, lato finale, out_dir)
        ("axe", "axe", 512, RELICS_OUT),
        ("mace", "mace", 512, RELICS_OUT),
        ("halberd", "halberd", 512, RELICS_OUT),
        ("vampire_blade", "vampire_blade", 512, RELICS_OUT),
        ("ranger_bow", "ranger_bow", 512, RELICS_OUT),
        ("item_hammer", "item_hammer", 128, HAMMER_OUT),
]


def process(rid_raw: str, rid_out: str, final_side: int, out_dir: Path) -> str:
        src = RAW / f"{rid_raw}.png"
        if not src.exists():
                return f"FAIL {rid_out}: raw mancante"
        # Le immagini Task 25 sono su sfondo CIANO.
        cyan = True
        im = Image.open(src).convert("RGB")
        arr = np.asarray(im)
        h, w, _ = arr.shape
        rgb = arr[..., :3].astype(np.float32)

        bg = pri.local_flood(rgb, cyan)
        bg_fraction = float(bg.mean())
        if bg_fraction < 0.12:
                old = pri.LOCAL_TOL
                pri.LOCAL_TOL = 45.0
                bg = pri.local_flood(rgb, cyan)
                bg_fraction = float(bg.mean())
                pri.LOCAL_TOL = old

        alpha = pri.fringe_alpha(rgb, bg, cyan)
        rgb = pri.despill_edges(rgb, alpha, cyan)
        alpha = pri.fringe_alpha(rgb, bg, cyan)
        # TASK 25: rimuovi i blob di vignette sopravvissuti negli angoli.
        alpha = _drop_background_blobs(alpha)

        opaque = alpha > 16
        if not opaque.any():
                return f"FAIL {rid_out}: key ha mangiato tutto"
        ys, xs = np.where(opaque)
        y0, y1, x0, x1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
        bbox_w, bbox_h = x1 - x0 + 1, y1 - y0 + 1
        coverage = max(bbox_w, bbox_h) / max(h, w)
        fill_frac = float(opaque.sum()) / float(max(1, bbox_w * bbox_h))
        notes = []
        if coverage < 0.30:
                notes.append(f"coverage bassa {coverage:.2f}")
        if fill_frac < 0.06:
                notes.append(f"oggetto sottile {fill_frac:.2f}")

        # Trim + margine 6% + crop quadrato + resize.
        mh = int(bbox_h * pri.MARGIN_FRAC)
        mw = int(bbox_w * pri.MARGIN_FRAC)
        y0m, y1m = max(0, y0 - mh), min(h, y1 + mh + 1)
        x0m, x1m = max(0, x0 - mw), min(w, x1 + mw + 1)
        rgba = np.dstack([rgb[y0m:y1m, x0m:x1m, :3], alpha[y0m:y1m, x0m:x1m]])
        img = Image.fromarray(rgba.astype(np.uint8))
        side = max(img.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2), img)
        if side > final_side:
                sq = sq.resize((final_side, final_side), Image.LANCZOS)

        out_dir.mkdir(parents=True, exist_ok=True)
        dst = out_dir / f"{rid_out}.png"
        sq.save(dst)
        note_s = ("; " + ", ".join(notes)) if notes else ""
        return (f"PASS {rid_out} [ciano]: {sq.size[0]}px, bg fill {bg_fraction:.2f}, "
                f"coverage {coverage:.2f}, fill_bbox {fill_frac:.2f}{note_s}")


def main() -> None:
        for rid_raw, rid_out, side, out_dir in JOBS:
                print(process(rid_raw, rid_out, side, out_dir))


if __name__ == "__main__":
        main()

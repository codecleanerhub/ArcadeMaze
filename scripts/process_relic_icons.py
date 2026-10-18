#!/usr/bin/env python3
"""Task 23 — Processing icone reliquie: chroma-key ADATTIVO -> PNG trasparenti.

PIPELINE FINALE (v5, dopo le lezioni v1..v4):
  * gli sfondi AI non sono magenta puro: sono vino/rosa con gradienti;
  * il flood deve usare CONTINUITA' LOCALE (segue i gradienti) + una
    GUARDIA DI FAMIGLIA COLORE (impedisce di attraversare gli oggetti);
  * il flood di "smoothness" è stato RIMOSSO: mangiava glow/fiamme/partes
    lisce degli oggetti (orbo arcuano, fiamme della corazza di fuoco);
  * gli oggetti le cui tinte CADONO nella famiglia vino (Fury cremisi,
    orbo viola) vengono generati su sfondo CIANO: famiglia opposta,
    contrasto cromatico massimo -> key pulita per costruzione.

FAMIGLIE:
  * magenta/vino (default): r > g + 25 AND b > g - 8
    (legno/oro/verde/argento/acciaio NON passano mai la guardia)
  * ciano (per Fury/orbo/fuoco): b > r + 25 AND g > r + 10
    (cremisi/viola/arancio/fiamme NON passano mai la guardia)

Passi: flood locale (famiglia+continuità) -> frangia semi-trasparente
(2px, guardia rilassata) -> despill magenta/ciano sui bordi -> trim ->
margine 6% -> crop quadrato -> resize 512 -> RGBA.
"""
from pathlib import Path
import numpy as np
from PIL import Image
from collections import deque

RAW_DIR = Path("/tmp/relic_gen")
OUT_DIR = Path("/home/z/my-project/ArcadeMaze/godot/assets/sprites/relics")

RELIC_IDS = [
        "sword", "axe", "mace", "halberd", "vampire_blade", "golem_hammer",
        "crossbow", "arcane_orb", "twin_daggers", "ranger_bow", "storm_rod",
        "alchemist_bombs",
        "golden", "dragon", "obsidian", "archmage", "fire", "fury",
]

## Chiave CIANO per gli oggetti con tinte nella famiglia vino/magenta.
CYAN_KEY = {"fury", "arcane_orb", "fire"}

FINAL_SIDE = 512
MARGIN_FRAC = 0.06

# --- famiglia magenta/vino ---
MAG_R_OVER_G = 25.0
MAG_B_OVER_G = -8.0
# --- famiglia ciano ---
CYA_B_OVER_R = 25.0
CYA_G_OVER_R = 10.0

LOCAL_TOL = 30.0


def family_mask(rgb: np.ndarray, cyan: bool, loose: bool = False) -> np.ndarray:
        r = rgb[..., 0]
        g = rgb[..., 1]
        b = rgb[..., 2]
        if cyan:
                ro = CYA_B_OVER_R * (0.5 if loose else 1.0)
                go = CYA_G_OVER_R * (0.5 if loose else 1.0)
                return (b > r + ro) & (g > r + go)
        ro = MAG_R_OVER_G * (0.5 if loose else 1.0)
        bo = MAG_B_OVER_G if not loose else -20.0
        return (r > g + ro) & (b > g + bo)


def local_flood(rgb: np.ndarray, cyan: bool) -> np.ndarray:
        """BFS dal bordo: famiglia colore + continuità col pixel genitore."""
        h, w, _ = rgb.shape
        fam = family_mask(rgb, cyan)
        bg = np.zeros((h, w), dtype=bool)
        queue = deque()
        for x in range(w):
                for y in (0, h - 1):
                        if fam[y, x] and not bg[y, x]:
                                bg[y, x] = True
                                queue.append((y, x))
        for y in range(h):
                for x in (0, w - 1):
                        if fam[y, x] and not bg[y, x]:
                                bg[y, x] = True
                                queue.append((y, x))
        while queue:
                y, x = queue.popleft()
                px = rgb[y, x]
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        ny, nx = y + dy, x + dx
                        if ny < 0 or ny >= h or nx < 0 or nx >= w:
                                continue
                        if bg[ny, nx] or not fam[ny, nx]:
                                continue
                        if float(np.abs(rgb[ny, nx] - px).max()) <= LOCAL_TOL:
                                bg[ny, nx] = True
                                queue.append((ny, nx))
        return bg


def fringe_alpha(rgb: np.ndarray, bg: np.ndarray, cyan: bool) -> np.ndarray:
        """Frangia: celle adiacenti allo sfondo con guardia rilassata ->
        alpha sfumato (anti-aliasing naturale sui bordi)."""
        h, w, _ = rgb.shape
        fam_loose = family_mask(rgb, cyan, loose=True)
        dil = bg.copy()
        for _ in range(2):
                d2 = dil.copy()
                d2[1:, :] |= dil[:-1, :]
                d2[:-1, :] |= dil[1:, :]
                d2[:, 1:] |= dil[:, :-1]
                d2[:, :-1] |= dil[:, 1:]
                dil = d2
        zone = dil & (~bg) & fam_loose

        dist_bg = np.full((h, w), 1e9, dtype=np.float32)
        dist_bg[bg] = 0.0
        for _ in range(3):
                d2 = dist_bg.copy()
                d2[1:, :] = np.minimum(d2[1:, :], dist_bg[:-1, :] + 1.0)
                d2[:-1, :] = np.minimum(d2[:-1, :], dist_bg[1:, :] + 1.0)
                d2[:, 1:] = np.minimum(d2[:, 1:], dist_bg[:, :-1] + 1.0)
                d2[:, :-1] = np.minimum(d2[:, :-1], dist_bg[:, 1:] + 1.0)
                dist_bg = d2
        ramp = np.clip((dist_bg - 0.5) / 2.0, 0.0, 1.0)
        alpha = np.full((h, w), 255, dtype=np.uint8)
        alpha[bg] = 0
        alpha = np.where(zone, (ramp * 255.0).astype(np.uint8), alpha)
        return alpha


def despill_edges(rgb: np.ndarray, alpha: np.ndarray, cyan: bool) -> np.ndarray:
        """Despill sui SOLI pixel di bordo (entro 3px dal trasparente).

    magenta: spill = min(r, b) - g > 0 -> r,b tirati verso g.
    ciano:   spill = min(g, b) - r > 0 -> g,b tirati verso r.
    Applicato solo alla frangia perimetrale (2-3px): invisibile a scala di
    gioco e non tocca i colori interni degli oggetti.
    """
        h, w, _ = rgb.shape
        transp = alpha < 128
        near = transp.copy()
        for _ in range(3):
                d2 = near.copy()
                d2[1:, :] |= near[:-1, :]
                d2[:-1, :] |= near[1:, :]
                d2[:, 1:] |= near[:, :-1]
                d2[:, :-1] |= near[:, 1:]
                near = d2
        zone = near & (~transp)
        r = rgb[..., 0]
        g = rgb[..., 1]
        b = rgb[..., 2]
        out = rgb.copy()
        k = 0.55
        if cyan:
                spill = np.minimum(g, b) - r
                m = zone & (spill > 0)
                out[..., 1] = np.where(m, r + (g - r) * k, g)
                out[..., 2] = np.where(m, r + (b - r) * k, b)
        else:
                spill = np.minimum(r, b) - g
                m = zone & (spill > 0)
                out[..., 0] = np.where(m, g + (r - g) * k, r)
                out[..., 2] = np.where(m, g + (b - g) * k, b)
        return out


def process_one(rid: str) -> str:
        src = RAW_DIR / f"{rid}.png"
        if not src.exists():
                return f"FAIL {rid}: raw mancante ({src})"
        cyan = rid in CYAN_KEY
        im = Image.open(src).convert("RGB")
        arr = np.asarray(im)
        h, w, _ = arr.shape
        rgb = arr[..., :3].astype(np.float32)

        bg = local_flood(rgb, cyan)
        bg_fraction = float(bg.mean())
        # RETRY più permissivo se il fill non è partito (sfondo anomalo).
        global LOCAL_TOL
        if bg_fraction < 0.12:
                old = LOCAL_TOL
                LOCAL_TOL = 45.0
                bg = local_flood(rgb, cyan)
                bg_fraction = float(bg.mean())
                LOCAL_TOL = old

        alpha = fringe_alpha(rgb, bg, cyan)
        rgb = despill_edges(rgb, alpha, cyan)
        alpha = fringe_alpha(rgb, bg, cyan)

        opaque = alpha > 16
        if not opaque.any():
                return f"FAIL {rid}: nessun pixel opaco (key ha mangiato tutto?)"
        ys, xs = np.where(opaque)
        y0, y1, x0, x1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
        bbox_w, bbox_h = x1 - x0 + 1, y1 - y0 + 1
        coverage = max(bbox_w, bbox_h) / max(h, w)
        touches_edge = (y0 <= 1) or (x0 <= 1) or (y1 >= h - 2) or (x1 >= w - 2)
        transparency = 1.0 - float(opaque.mean())
        fill_frac = float(opaque.sum()) / float(max(1, bbox_w * bbox_h))
        verdict = "PASS"
        notes = []
        if coverage < 0.30:
                verdict = "WARN"
                notes.append(f"coverage bassa {coverage:.2f}")
        if coverage > 0.985:
                notes.append(f"coverage {coverage:.2f}")
                verdict = "WARN"
        if touches_edge:
                notes.append("bbox tocca il bordo")
        if transparency > 0.95:
                verdict = "WARN"
                notes.append(f"trasparenza {transparency:.2f}")
        if fill_frac < 0.06:
                verdict = "WARN"
                notes.append(f"oggetto sottile {fill_frac:.2f}")

        # Trim + margine + crop quadrato.
        mh = int(bbox_h * MARGIN_FRAC)
        mw = int(bbox_w * MARGIN_FRAC)
        y0m = max(0, y0 - mh)
        y1m = min(h, y1 + mh + 1)
        x0m = max(0, x0 - mw)
        x1m = min(w, x1 + mw + 1)
        rgba = np.dstack([rgb[y0m:y1m, x0m:x1m, :3], alpha[y0m:y1m, x0m:x1m]])
        img = Image.fromarray(rgba.astype(np.uint8))
        side = max(img.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2), img)
        if side > FINAL_SIDE:
                sq = sq.resize((FINAL_SIDE, FINAL_SIDE), Image.LANCZOS)

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        dst = OUT_DIR / f"{rid}.png"
        sq.save(dst)
        key_s = "ciano" if cyan else "magenta"
        note_s = ("; " + ", ".join(notes)) if notes else ""
        return (f"{verdict} {rid} [{key_s}]: {sq.size[0]}px, bg fill {bg_fraction:.2f}, "
                f"coverage {coverage:.2f}, fill_bbox {fill_frac:.2f}, "
                f"trasparenza {transparency:.2f}{note_s}")


def main() -> None:
        results = [process_one(rid) for rid in RELIC_IDS]
        for r in results:
                print(r)
        n_fail = sum(1 for r in results if r.startswith("FAIL"))
        n_warn = sum(1 for r in results if r.startswith("WARN"))
        print(f"\n==== {len(results)} icone: {len(results) - n_fail - n_warn} PASS, "
              f"{n_warn} WARN, {n_fail} FAIL -> {OUT_DIR} ====")


if __name__ == "__main__":
        main()

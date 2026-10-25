#!/usr/bin/env python3
"""QA numerica per gli asset PixelLab v2 (§8.2 e lezioni §12.29/12.33).

Controlli:
  - bordi trasparenti puliti (nessun pixel semitrasparente sul bordo frame)
  - palette limitata (pixel-art: default max 96 colori unici)
  - coverage (pixel opachi / totali) entro range parametrico
  - diff frame adiacenti (animati): 3-55% = OK; <3% frame statico;
    1-3% near-dup -> da scartare con ping-pong [0,1,2,3,4,3]
  - allineamento piedi y=56 (sheet personaggi/entità 64px)
  - fedeltà cromatica: distanza media hue dai colori dominanti del reference
"""
from __future__ import annotations

import colorsys
from PIL import Image


def _rgb_hue(r: float, g: float, b: float) -> float:
    h, _, _ = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return h * 360.0


def check_transparent_edges(img: Image.Image) -> list[str]:
    """Nessun pixel con alpha parziale sul bordo esterno del frame."""
    errors = []
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    for x in range(w):
        for y in (0, h - 1):
            a = px[x, y][3]
            if 0 < a < 250:
                errors.append(f"alpha parziale {a} sul bordo ({x},{y})")
                if len(errors) > 4:
                    return errors
    for y in range(h):
        for x in (0, w - 1):
            a = px[x, y][3]
            if 0 < a < 250:
                errors.append(f"alpha parziale {a} sul bordo ({x},{y})")
                if len(errors) > 4:
                    return errors
    return errors


def check_palette(img: Image.Image, max_colors: int = 96) -> list[str]:
    rgba = img.convert("RGBA")
    colors = {(p[0], p[1], p[2]) for p in rgba.getdata() if p[3] > 0}
    if len(colors) > max_colors:
        return [f"palette troppo larga: {len(colors)} colori (max {max_colors})"]
    return []


def check_coverage(img: Image.Image, lo: float = 8.0, hi: float = 60.0) -> list[str]:
    """Percentuale pixel opachi. Item/icone: 8-60% (personaggi: 16-41%)."""
    rgba = img.convert("RGBA")
    total = rgba.size[0] * rgba.size[1]
    opaque = sum(1 for p in rgba.getdata() if p[3] > 0)
    cov = 100.0 * opaque / total
    if cov < lo:
        return [f"coverage troppo bassa {cov:.1f}% (min {lo})"]
    if cov > hi:
        return [f"coverage troppo alta {cov:.1f}% (max {hi})"]
    return []


def frame_diff_pct(a: Image.Image, b: Image.Image) -> float:
    """% pixel cambiati (contenuto, non solo posizione) tra due frame."""
    ra, rb = a.convert("RGBA"), b.convert("RGBA")
    if ra.size != rb.size:
        return 100.0
    pa, pb = ra.load(), rb.load()
    w, h = ra.size
    changed = 0
    for x in range(0, w, 2):  # campionamento 1/4 per velocità
        for y in range(0, h, 2):
            va, vb = pa[x, y], pb[x, y]
            if (va[3] > 0) != (vb[3] > 0):
                changed += 1
            elif va[3] > 0 and (
                abs(va[0] - vb[0]) > 24 or abs(va[1] - vb[1]) > 24
                or abs(va[2] - vb[2]) > 24
            ):
                changed += 1
    return 100.0 * changed / ((w // 2) * (h // 2))


def check_frame_diffs(frames: list[Image.Image]) -> list[str]:
    """Diffs adiacenti: ogni coppia deve stare in 3-55% (no statico, no near-dup)."""
    errors = []
    for i in range(len(frames) - 1):
        d = frame_diff_pct(frames[i], frames[i + 1])
        if d < 3.0:
            errors.append(f"frame {i}->{i+1}: diff {d:.1f}% < 3% (frame STATICO)")
        elif d < 1.0 + 2.0:  # near-dup band 1-3% segnalata
            if d >= 1.0:
                errors.append(f"frame {i}->{i+1}: diff {d:.1f}% in banda near-dup (1-3%) — scartare e ping-pong")
        elif d > 55.0:
            errors.append(f"frame {i}->{i+1}: diff {d:.1f}% > 55% (drift eccessivo)")
    return errors


def check_feet_y56(img: Image.Image, frame_h: int = 64) -> list[str]:
    """L'ultima riga di pixel opachi deve stare a y=56 (anchor personaggi)."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    last_opaque = -1
    for y in range(h - 1, -1, -1):
        found = False
        for x in range(0, w, 2):
            if px[x, y][3] > 0:
                found = True
                break
        if found:
            last_opaque = y
            break
    if last_opaque < 0:
        return ["frame vuoto (nessun pixel opaco)"]
    expected = frame_h - 8  # y=56 su frame 64
    if abs(last_opaque - 56) > 6 and abs(last_opaque - expected) > 6:
        return [f"piedi a y={last_opaque} (atteso 56±6 su frame {frame_h}px)"]
    return []


def dominant_hues(img: Image.Image, top: int = 5) -> list[float]:
    """Hue dei colori dominanti (pesati per occorrenza), in gradi 0-360."""
    rgba = img.convert("RGBA")
    counts: dict[tuple[int, int, int], int] = {}
    for p in rgba.getdata():
        if p[3] > 128:
            counts[(p[0], p[1], p[2])] = counts.get((p[0], p[1], p[2]), 0) + 1
    top_cols = sorted(counts.items(), key=lambda kv: -kv[1])[: top * 3]
    hues = []
    for (r, g, b), _ in top_cols:
        if max(r, g, b) - min(r, g, b) < 18:  # skip quasi-grigi
            continue
        hues.append(_rgb_hue(r, g, b))
        if len(hues) >= top:
            break
    return hues


def check_chromatic_fidelity(gen: Image.Image, ref: Image.Image,
                             tol_hue: float = 40.0, min_match: float = 0.34) -> list[str]:
    """Almeno 1/3 degli hue dominanti del generato deve stare vicino al reference.

    ECCEZIONE monocromia: se il generato non ha hue saturi ma anche il
    reference è prevalentemente neutro (item scuri tipo mina di ferro),
    il check passa — l'assenza di hue È la fedeltà cromatica giusta."""
    ref_hues = dominant_hues(ref)
    if not ref_hues:
        return []  # reference già neutro: niente da matchare
    gen_hues = dominant_hues(gen, top=8)
    if not gen_hues:
        # il generato è monocromo: passa SOLO se il reference è per lo più neutro
        rgba = ref.convert("RGBA")
        counts: dict[tuple[int, int, int], int] = {}
        for p in rgba.getdata():
            if p[3] > 128:
                counts[(p[0], p[1], p[2])] = counts.get((p[0], p[1], p[2]), 0) + 1
        top_cols = sorted(counts.items(), key=lambda kv: -kv[1])[:15]
        neutral = sum(1 for (r, g, b), _ in top_cols if max(r, g, b) - min(r, g, b) < 26)
        if neutral >= len(top_cols) // 2:
            return []  # reference prevalentemente neutro: monocromia corretta
        return ["nessun hue saturo nel generato ma reference colorato"]
    matched = 0
    for gh in gen_hues:
        for rh in ref_hues:
            d = abs(gh - rh)
            d = min(d, 360.0 - d)
            if d <= tol_hue:
                matched += 1
                break
    ratio = matched / len(gen_hues)
    if ratio < min_match:
        return [f"fedeltà cromatica {ratio:.0%} < {min_match:.0%} "
                f"(gen {['%.0f' % h for h in gen_hues]} vs ref {['%.0f' % h for h in ref_hues]})"]
    return []


def qa_static(img: Image.Image, ref: Image.Image | None = None,
              max_colors: int = 96, cov: tuple[float, float] = (8.0, 60.0)) -> list[str]:
    """QA completa per uno statico (item/icona/prop)."""
    errors = check_transparent_edges(img)
    errors += check_palette(img, max_colors)
    errors += check_coverage(img, *cov)
    if ref is not None:
        errors += check_chromatic_fidelity(img, ref)
    return errors


def qa_anim_frames(frames: list[Image.Image], ref: Image.Image | None = None,
                   feet_check: bool = False) -> list[str]:
    """QA completa per i frame di un'animazione 4-frame."""
    errors = []
    for i, f in enumerate(frames):
        e = check_transparent_edges(f)
        errors += [f"[f{i}] {x}" for x in e]
    errors += check_frame_diffs(frames)
    if ref is not None and frames:
        errors += check_chromatic_fidelity(frames[0], ref)
    if feet_check and frames:
        errors += check_feet_y56(frames[0])
    return errors


def report(entity_id: str, errors: list[str]) -> bool:
    if errors:
        print(f"[QA] ✗ {entity_id}: {len(errors)} problemi")
        for e in errors:
            print(f"      - {e}")
        return False
    print(f"[QA] ✓ {entity_id}: PASS")
    return True

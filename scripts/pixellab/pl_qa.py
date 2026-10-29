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


def regional_diff_pct(a: Image.Image, b: Image.Image) -> float:
    """% pixel cambiati RELATIVA alla regione soggetto (bbox unione alpha).

    Lezione Task 54: per animazioni parziali (fiamma di torcia su corpo
    stabile) il diff globale sul canvas sottostima il moto: 2% globale può
    essere 12% della sola regione animata. Si conta la NATURA del cambio
    nella sua regione (§12.34).
    """
    ra, rb = a.convert("RGBA"), b.convert("RGBA")
    if ra.size != rb.size:
        return 100.0
    # bbox unione dei pixel opachi
    boxes = [im.getbbox() for im in (ra, rb) if im.getbbox()]
    if not boxes:
        return 0.0
    x0 = min(bx[0] for bx in boxes); y0 = min(bx[1] for bx in boxes)
    x1 = max(bx[2] for bx in boxes); y1 = max(bx[3] for bx in boxes)
    pa, pb = ra.load(), rb.load()
    changed = 0
    for x in range(x0, x1):
        for y in range(y0, y1):
            va, vb = pa[x, y], pb[x, y]
            if (va[3] > 0) != (vb[3] > 0):
                changed += 1
            elif va[3] > 0 and (
                abs(va[0] - vb[0]) > 24 or abs(va[1] - vb[1]) > 24
                or abs(va[2] - vb[2]) > 24
            ):
                changed += 1
    area = max(1, (x1 - x0) * (y1 - y0))
    return 100.0 * changed / area


def aligned_residual_diff(a: Image.Image, b: Image.Image,
                          max_shift: int = 4) -> float:
    """Residuo % dopo il MIGLIOR allineamento di b su a (shift ±max_shift).

    TASK 71 (feedback utente "immagine statica che si sposta traslando"):
    la diff globale/regional passa anche quando un frame e' SOLO una
    traslazione dell'altro (tutti i pixel "cambiano" perche' si spostano).
    Qui riallineiamo b su a con tutti gli shift interi ±max_shift e
    teniamo il residuo MINIMO: se anche il migliore allineamento lascia
    poco residuo, il frame non anima nulla — e' puro slide.
    """
    ra, rb = a.convert("RGBA"), b.convert("RGBA")
    if ra.size != rb.size:
        return 100.0
    w, h = ra.size
    # bbox unione dei pixel opachi (regione soggetto, come regional_diff)
    boxes = [im.getbbox() for im in (ra, rb) if im.getbbox()]
    if not boxes:
        return 0.0
    x0 = min(bx[0] for bx in boxes); y0 = min(bx[1] for bx in boxes)
    x1 = max(bx[2] for bx in boxes); y1 = max(bx[3] for bx in boxes)
    pa, pb = ra.load(), rb.load()
    best: float | None = None
    for dy in range(-max_shift, max_shift + 1):
        for dx in range(-max_shift, max_shift + 1):
            changed = 0
            for x in range(x0, x1):
                for y in range(y0, y1):
                    va = pa[x, y]
                    sx, sy = x + dx, y + dy
                    if 0 <= sx < w and 0 <= sy < h:
                        vb = pb[sx, sy]
                    else:
                        vb = (0, 0, 0, 0)
                    if (va[3] > 0) != (vb[3] > 0):
                        changed += 1
                    elif va[3] > 0 and (
                        abs(va[0] - vb[0]) > 24 or abs(va[1] - vb[1]) > 24
                        or abs(va[2] - vb[2]) > 24
                    ):
                        changed += 1
            area = max(1, (x1 - x0) * (y1 - y0))
            res = 100.0 * changed / area
            if best is None or res < best:
                best = res
    return best if best is not None else 100.0


def check_slide_and_duplicates(frames: list[Image.Image],
                               dup_pct: float = 0.7,
                               slide_pct: float = 5.0) -> list[str]:
    """TASK 71: blocca i cicli degenere tipo "pedina che si trascina".

    - DUPLICATI (tutte le coppie): il vecchio unicorn_ally aveva frame 0==2
      e 1==3 al bit -> ciclo leggibile come 2-frame stutter.
    - PURO SLIDE (coppie adiacenti): frame 1 era frame 0 traslato 1px ->
      "immagine statica che si sposta traslando". Il residuo dopo il
      miglior allineamento deve restare > slide_pct.
    """
    errors: list[str] = []
    n = len(frames)
    for i in range(n):
        for j in range(i + 1, n):
            g = frame_diff_pct(frames[i], frames[j])
            if g < dup_pct:
                errors.append(f"frame {i} e {j} DUPLICATI (diff {g:.1f}% < "
                              f"{dup_pct}%) — ciclo degenere")
    for i in range(n - 1):
        r = aligned_residual_diff(frames[i], frames[i + 1])
        if r < slide_pct:
            errors.append(f"frame {i}->{i+1}: PURO SLIDE (residuo {r:.1f}% "
                          f"post-allineamento < {slide_pct}%) — il frame non "
                          f"anima pose, si limita a traslare")
    return errors


def check_frame_diffs(frames: list[Image.Image]) -> list[str]:
    """Diffs adiacenti: GLOBAL 3-55% OPPURE REGIONAL >=6% = moto OK.

    Fallisce solo se il frame è statico su ENTRAMBE le metriche
    (global <3% e regional <6%) o se c'è drift eccessivo (global >55%,
    regional >75%)."""
    errors = []
    for i in range(len(frames) - 1):
        g = frame_diff_pct(frames[i], frames[i + 1])
        r = regional_diff_pct(frames[i], frames[i + 1])
        if g < 3.0 and r < 6.0:
            errors.append(f"frame {i}->{i+1}: diff globale {g:.1f}% e regionale "
                          f"{r:.1f}% — frame STATICO sulla regione animata")
        elif 1.0 <= g < 3.0 and r < 6.0:
            errors.append(f"frame {i}->{i+1}: banda near-dup (g {g:.1f}%/r {r:.1f}%) "
                          f"— scartare e ping-pong")
        elif g > 55.0 and r > 75.0:
            errors.append(f"frame {i}->{i+1}: drift eccessivo (g {g:.1f}%/r {r:.1f}%)")
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
    errors += check_slide_and_duplicates(frames)
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

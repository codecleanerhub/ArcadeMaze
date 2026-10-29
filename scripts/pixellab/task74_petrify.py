#!/usr/bin/env python3
"""task74_petrify.py — TASK 74: statua del cavaliere via PETRIFICAZIONE
animate-v3 dal frame REALE dell'alleato.

PERCHE': due tentativi pixflux statici (statua 29px e 25px di larghezza
vs alleato 54px) hanno mostrato che il text-to-image "statue" collassa
sempre verso la colonna monumentale sottile, ANCHE con anchor pietra
del frame alleato (il color_image e' anchor di PALETTE, non di forma).
L'utente vuole la statua "piu' simile alla sua versione attivata":

STRATEGIA INVERSA (lezione Task 73 rovesciata): invece di generare una
statua sperando somigli all'alleato, parto DALL'ALLEATO (frame 3, il piu'
statuario) come first_frame di animate-with-text-v3 e chiedo la
PIETRIFICAZIONE: la forma resta identica al 100% (animate v3 preserva
il first frame — e' come sono stati fatti gli sheet alleati), il
materiale diventa pietra (colori che si dissanguano in grigio, crepe,
mantello che si irrigidisce).

Il frame 3 (ultimo) = statua piu' pietrificata.

Poi: rimozione sfondo, valutazione saturazione residua, eventuale
remap in rampa pietra (fallback deterministico), save in
out/knight_statue/petrified/*.png.

Uso: python3 scripts/pixellab/task74_petrify.py [--remap-forced]
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np
from PIL import Image

import pl_api
import pl_integrate

SHEET = os.path.join(HERE, "..", "..", "godot", "assets", "sprites",
                     "knight_ally_sheet.png")
OUT_DIR = os.path.join(HERE, "out", "knight_statue")
PETRI_DIR = os.path.join(OUT_DIR, "petrified")
os.makedirs(PETRI_DIR, exist_ok=True)

FRAME = 3          # frame piu' statuario del walk cycle
FIRST_FRAME = os.path.join(OUT_DIR, "petrify_first.png")
ACTION = (
    "the marching knight slowly petrifies into an ancient stone statue: "
    "all colors drain away into weathered gray stone, fine cracks spread "
    "across the armor plates, the cloak stiffens into solid rock, the "
    "metal turns to carved gray stone with chipped edges, the pose "
    "freezes completely, subtle moss appears on the boots, no movement, "
    "no camera movement, background stays transparent"
)

# rampa pietra (identica a gen_knight_statue_anchor.py)
RAMP = [
    (54, 52, 68), (84, 82, 98), (118, 114, 108),
    (150, 146, 138), (182, 178, 168), (214, 210, 198),
]


def saturation_stats(img: Image.Image) -> tuple[float, float]:
    """(sat media, sat max) sui pixel opachi."""
    a = np.array(img.convert("RGBA"))
    op = a[:, :, 3] > 128
    if not op.any():
        return 0.0, 0.0
    mx = a[:, :, :3].max(axis=2).astype(int)
    mn = a[:, :, :3].min(axis=2).astype(int)
    sat = (mx - mn)[op]
    return float(sat.mean()), float(sat.max())


def stone_remap(img: Image.Image) -> Image.Image:
    """Remap luminanza per-percentili -> rampa pietra (alpha preservato)."""
    a = np.array(img.convert("RGBA"))
    op = a[:, :, 3] > 10
    lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2])
    vals = np.sort(lum[op])
    n = len(vals)
    thr = [vals[int(q * (n - 1))] for q in (1/6, 2/6, 3/6, 4/6, 5/6)]
    li = np.digitize(lum, thr)
    out = np.zeros_like(a)
    for k, col in enumerate(RAMP):
        sel = op & (li == k)
        out[sel, 0], out[sel, 1], out[sel, 2] = col
    out[:, :, 3] = np.where(op, 255, 0)
    return Image.fromarray(out)


def main() -> None:
    forced = "--remap-forced" in sys.argv

    # 1) first frame: ally frame 3 su canvas 256x256 (4x NEAREST)
    sheet = Image.open(SHEET).convert("RGBA")
    frame = sheet.crop((FRAME * 64, 0, (FRAME + 1) * 64, 64))
    big = frame.resize((256, 256), Image.NEAREST)
    big.save(FIRST_FRAME)
    print(f"first frame: {FIRST_FRAME}")

    # 2) submit + poll (job_id persistito PRIMA del poll — anti-doppio-POST)
    state_f = os.path.join(HERE, "state", "knight_statue_petrify.json")
    os.makedirs(os.path.dirname(state_f), exist_ok=True)
    import json
    st = {}
    if os.path.isfile(state_f):
        with open(state_f) as f:
            st = json.load(f)
    if st.get("job_id"):
        job_id = st["job_id"]
        print(f"resume job {job_id}")
    else:
        job_id = pl_api.submit_animate_with_text_v3(
            first_frame_path=FIRST_FRAME, action=ACTION,
            frame_count=4, seed=74)
        st["job_id"] = job_id
        with open(state_f, "w") as f:
            json.dump(st, f, indent=2)

    raw = pl_api.poll_background_job(job_id)
    raw_dir = os.path.join(PETRI_DIR, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    for i, b64 in enumerate(raw):
        pl_api.save_b64_image(b64, os.path.join(raw_dir, f"r{i}.png"))

    frames = raw[1:] if len(raw) > 4 else raw  # r0 = reference
    frames = frames[:4]
    for i, b64 in enumerate(frames):
        pl_api.save_b64_image(b64, os.path.join(PETRI_DIR, f"f{i}.png"))
    print(f"frame salvati: {len(frames)}")

    # 3) post-processing del frame 3 (il piu' pietrificato)
    last = os.path.join(PETRI_DIR, "f3.png")
    img = Image.open(last).convert("RGBA")
    img = pl_integrate.remove_solid_background(img, tol=34)
    mean_sat, max_sat = saturation_stats(img)
    print(f"f3 post-bg: sat media {mean_sat:.1f}, max {max_sat:.1f}")
    # soglia: statua di pietra deve avere sat media bassa; se PixelLab ha
    # lasciato colori (armatura argento sat alta per i riflessi blu),
    # remap deterministico in rampa pietra
    if forced or mean_sat > 18.0 or max_sat > 90.0:
        print("-> remap in rampa pietra (fallback deterministico)")
        img = stone_remap(img)
        mean_sat2, max_sat2 = saturation_stats(img)
        print(f"post-remap: sat media {mean_sat2:.1f}, max {max_sat2:.1f}")
    out_f = os.path.join(PETRI_DIR, "statue_final.png")
    img.save(out_f)
    print(f"statua finale: {out_f}")

    a = np.array(img)
    ys, xs = np.nonzero(a[:, :, 3] > 10)
    if len(xs):
        print(f"contenuto 256: x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}] "
              f"({xs.max()-xs.min()+1}x{ys.max()-ys.min()+1}) — ally era 216x224")


if __name__ == "__main__":
    main()

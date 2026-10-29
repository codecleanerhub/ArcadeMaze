#!/usr/bin/env python3
"""spawn_blink_analyze.py — analisi dei frame movie-mode del lampeggio di
nascita del player (ex test_spawn_guard_visual.gd, TASK 40).

Perche' questa pipeline: il vecchio test leggeva il viewport con
get_image() dentro _physics_process agganciandosi alle fasi ON/OFF del
blink; sotto llvmpipe/Xvfb (sandbox) il rendering in modalita' interattiva
scorre a ~8-15 fps effettivi e i frame completati IN RITARDO rispetto alla
fisica, quindi il campionamento fase-agganciato mischia frame ON e OFF e
il test fallisce anche a gioco perfetto. La pipeline --write-movie
(fixed-fps 30, frame deterministici, quella usata da tutti gli screenshot
di verifica dei task 84-91) e' immune al problema: si analizza la SERIE
TEMPORALE della luminanza del crop player cercando l'oscillazione del
blink.

Criteri PASS (sul crop 80x80 centrato sul player):
  1. durante la finestra di guardia (frame 70..100): ampiezza
     max-min >= 10 su 255 (misurato a gioco corretto: ~15-18);
  2. almeno 3 transizioni salite+discese in quella finestra (periodo
     atteso 250ms = ~7.5 frame a 30fps);
  3. dopo la guardia (frame 105..145): stabile (range < 8): il corpo
     resta solido, niente lampeggio residuo.
NOTA metrica: il player nasce su un PAD di spawn CHIARO, quindi le fasi
OFF (corpo al 15%) sono PIU' luminose delle ON (corpo solido che copre il
pad): l'oscillazione e' invertita ma l'ampiezza e' il segnale.

Uso: spawn_blink_analyze.py <dir_frame_png> [meta_pos.txt]
Exit 0 = PASS, 1 = FAIL (messaggi `[TEST]`/`[TEST FAIL]` come gli altri test).
"""
import sys
import glob
import os
from PIL import Image

FPS = 30
CROP = 40          # semi-larghezza del crop (80x80)
WIN_BLINK = (70, 100)   # frame: overlay boot (2.2s=66f) chiuso, guardia attiva
WIN_STABLE = (105, 145)  # frame: guardia (3s+0.5 caricamento) finita
MIN_AMP = 10.0
MAX_STABLE_RANGE = 8.0
MIN_TRANSITIONS = 3


def mean_lum(img, cx, cy):
    box = (cx - CROP, cy - CROP, cx + CROP, cy + CROP)
    if box[0] < 0 or box[1] < 0 or box[2] > img.width or box[3] > img.height:
        return None
    px = list(img.crop(box).convert("L").getdata())
    return sum(px) / float(len(px))


def main():
    if len(sys.argv) < 2:
        print("uso: spawn_blink_analyze.py <dir_frame_png> [meta_pos.txt]")
        return 2
    frame_dir = sys.argv[1]
    meta_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/spawn_blink_meta.txt"
    frames = sorted(glob.glob(os.path.join(frame_dir, "frame*.png")))
    if len(frames) < WIN_STABLE[1]:
        print("[TEST FAIL] frame insufficienti: %d (servono %d)" % (
            len(frames), WIN_STABLE[1]))
        return 1
    cx, cy = 96, 176  # default: cella di nascita P1
    try:
        with open(meta_path) as f:
            parts = f.read().split()
            cx, cy = int(parts[0]), int(parts[1])
    except (OSError, ValueError, IndexError):
        print("[TEST] meta pos non leggibile: uso default (%d,%d)" % (cx, cy))

    vals = []
    for path in frames:
        v = mean_lum(Image.open(path), cx, cy)
        if v is None:
            v = -1.0
        vals.append(v)

    blink = vals[WIN_BLINK[0]:WIN_BLINK[1]]
    stable = vals[WIN_STABLE[0]:WIN_STABLE[1]]
    amp = max(blink) - min(blink)
    mid = (max(blink) + min(blink)) / 2.0
    transitions = 0
    for i in range(1, len(blink)):
        if (blink[i - 1] < mid) != (blink[i] < mid):
            transitions += 1
    stable_range = max(stable) - min(stable)

    print("[TEST] luminanza crop player (pos %d,%d):" % (cx, cy))
    print("[TEST]   finestra guardia f%d-%d: min=%.1f max=%.1f ampiezza=%.1f "
          "transizioni=%d" % (WIN_BLINK[0], WIN_BLINK[1], min(blink),
                              max(blink), amp, transitions))
    print("[TEST]   finestra post-guardia f%d-%d: range=%.1f" % (
        WIN_STABLE[0], WIN_STABLE[1], stable_range))

    ok = True
    if amp < MIN_AMP:
        print("[TEST FAIL] il corpo del player NON lampeggia a schermo "
              "(ampiezza %.1f < %.1f)" % (amp, MIN_AMP))
        ok = False
    else:
        print("[TEST] OK ampiezza blink %.1f >= %.1f" % (amp, MIN_AMP))
    if transitions < MIN_TRANSITIONS:
        print("[TEST FAIL] oscillazione assente/incompleta: %d transizioni "
              "(attese >= %d, periodo ~7.5 frame)" % (
                  transitions, MIN_TRANSITIONS))
        ok = False
    else:
        print("[TEST] OK oscillazione periodica: %d transizioni" % transitions)
    if stable_range > MAX_STABLE_RANGE:
        print("[TEST FAIL] lampeggio residuo dopo la guardia "
              "(range %.1f > %.1f)" % (stable_range, MAX_STABLE_RANGE))
        ok = False
    else:
        print("[TEST] OK corpo stabile e solido dopo la guardia "
              "(range %.1f)" % stable_range)

    if ok:
        print("[TEST] test_spawn_guard_visual: TUTTO VERDE")
        return 0
    print("[TEST] test_spawn_guard_visual: FALLITO")
    return 1


if __name__ == "__main__":
    sys.exit(main())

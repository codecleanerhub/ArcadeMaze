#!/usr/bin/env python3
"""Task 23 — Processing sfondo SCHERMATA BONUS (bg_bonus.png): fucina/armeria.

Pipeline coerente con gli altri background (process_bg_credits.py):
  * sorgente 1344x768 widescreen (lezione Task 16: niente quadrati che il
    cover-fit trancia sul 16:9);
  * FIX bande (lezione Task 17): verifica NUMERICA per-riga delle bande
    chiare/scure uniformi ai bordi -> se presenti, nero puro + gradiente;
  * quantize MEDIANCUT 256 colori + dither Floyd-Steinberg (look del gioco);
  * salvataggio in godot/assets/backgrounds/bg_bonus.png + preview.
"""
from pathlib import Path
import numpy as np
from PIL import Image

SRC = Path("/tmp/relic_gen/bg_bonus_raw.png")
DST_GODOT = Path("/home/z/my-project/ArcadeMaze/godot/assets/backgrounds/bg_bonus.png")
DST_PREVIEW = Path("/home/z/my-project/download/bg_bonus_preview.png")

GRAD = 40  # righe di sfumatura nera (se servono)


def remove_bands(arr: np.ndarray) -> np.ndarray:
        """Bande uniformi chiare ai bordi -> nero con sfumatura (Task 17)."""
        h, w, _ = arr.shape
        rowmean = arr.mean(axis=(1, 2))
        rowstd = arr.std(axis=(1, 2))
        white = (rowmean > 100) & (rowstd < 60)
        top_end = 0
        while top_end < h and white[top_end]:
                top_end += 1
        bot_start = h
        while bot_start > 0 and white[bot_start - 1]:
                bot_start -= 1
        print(f"banda chiara sopra: righe 0..{top_end - 1} ({top_end}px); "
              f"sotto: righe {bot_start}..{h - 1} ({h - bot_start}px)")
        if top_end > 0 and top_end < h // 4:
                arr[:top_end, :, :] = 0.0
                for i in range(GRAD):
                        y = top_end + i
                        if y >= h:
                                break
                        arr[y, :, :] *= (i + 1) / (GRAD + 1)
        if bot_start < h and (h - bot_start) < h // 4:
                arr[bot_start:, :, :] = 0.0
                for i in range(GRAD):
                        y = bot_start - 1 - i
                        if y < 0:
                                break
                        arr[y, :, :] *= (i + 1) / (GRAD + 1)
        return arr


def main() -> None:
        im = Image.open(SRC).convert("RGB")
        print(f"sorgente: {im.size} {im.mode}")
        arr = np.asarray(im).astype(float)

        # 1) FIX bande (Task 17).
        arr = remove_bands(arr)

        # 2) Verifica NUMERICA bordi (lezione Task 17: la QA VLM non basta).
        rowmean = arr.mean(axis=(1, 2))
        print(f"luminanza media bordi: prima riga {rowmean[0]:.1f}, "
              f"ultima riga {rowmean[-1]:.1f}")
        out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

        # 3) Quantize 256 colori + dithering (stile degli altri bg).
        q = out.quantize(colors=256, method=Image.MEDIANCUT,
                         dither=Image.Dither.FLOYDSTEINBERG)
        final = q.convert("RGB")

        DST_GODOT.parent.mkdir(parents=True, exist_ok=True)
        final.save(DST_GODOT)
        DST_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
        final.save(DST_PREVIEW)

        # 4) Verifica finale per-riga: nessuna banda uniforme grigia.
        farr = np.asarray(final).astype(float)
        fmean = farr.mean(axis=(1, 2))
        fstd = farr.std(axis=(1, 2))
        bad = ((fmean > 60) & (fstd < 40)).sum()
        print(f"righe uniformi-chiare residue (mean>60, std<40): {bad}")
        print(f"salvato: {DST_GODOT} ({final.size[0]}x{final.size[1]})")
        if bad > 0:
                print("WARN: righe sospette — verificare visivamente")


if __name__ == "__main__":
        main()

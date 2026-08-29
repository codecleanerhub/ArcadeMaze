#!/usr/bin/env python3
"""
reprocess_boss_sprites.py - Riapplica SOLO il post-processing ai raw AI
esistenti per i 3 boss problematici (kraken, stone golem, lich).

NON rigenera i raw AI (lenti, costosi). Solo post-processing:
1. Per ogni raw esistente in /tmp/boss_anim_v2/, applica il process_frame
   migliorato (con scale uniforme basata su target_height).
2. Normalizza le dimensioni dei 4 frame per evitare effetto zoom/salto.
3. Compone lo spritesheet 256x64 e salva.

Utile quando si vuole iterare sul post-processing senza rigenerare i raw.
"""
import sys
import os
import numpy as np
sys.path.insert(0, '/home/z/my-project/ArcadeMaze/scripts')
from gen_boss_animations_v2 import (
    RAW_DIR, SPRITES_DIR, SPRITE_SIZE, N_FRAMES,
    process_frame, compose_spritesheet, write_meta, BOSSES
)


def reprocess_one(sprite_id):
    """Rielabora un boss dai raw esistenti."""
    print(f"\n[Reprocess] {sprite_id}")

    # Verifica che esistano i 4 raw
    raw_paths = []
    for i in range(N_FRAMES):
        p = RAW_DIR / f"{sprite_id}_frame{i}_raw.png"
        if not p.exists():
            print(f"  [ERROR] {p.name} non trovato, skip")
            return False
        raw_paths.append(p)

    # Processa frame 0 per trovare target_height
    print(f"  Frame 0: post-processing per trovare altezza riferimento...")
    frame0, target_height = process_frame(raw_paths[0])
    if frame0 is None:
        print(f"  [ERROR] Post-processing frame 0 fallito")
        return False
    print(f"     Altezza riferimento (raw 1024): {target_height}px")

    # Processa gli altri 3 frame usando target_height
    frames = [frame0]
    for i in range(1, N_FRAMES):
        print(f"  Frame {i}: post-processing (stessa altezza del frame 0)...")
        frame_i, _ = process_frame(raw_paths[i], target_height=target_height)
        if frame_i is None:
            print(f"  [WARN] Post-processing frame {i} fallito, uso frame 0")
            frames.append(frame0.copy())
        else:
            frames.append(frame_i)

    # Composizione spritesheet (include normalizzazione dimensioni)
    out_path = SPRITES_DIR / f"{sprite_id}_sheet.png"
    sheet = compose_spritesheet(frames, out_path)

    # Statistiche
    transparent = int(np.sum(sheet[..., 3] == 0))
    total = sheet.shape[0] * sheet.shape[1]
    print(f"  [OK] {out_path.name}: {out_path.stat().st_size} bytes, "
          f"trasparenti={transparent}/{total} ({transparent/total*100:.1f}%)")

    # Statistiche per frame (post-normalizzazione)
    for i in range(N_FRAMES):
        f = sheet[:, i * SPRITE_SIZE:(i + 1) * SPRITE_SIZE]
        alpha = f[..., 3]
        non_tr = (alpha > 0).sum()
        rows = np.any(alpha > 0, axis=1)
        cols = np.any(alpha > 0, axis=0)
        if rows.any():
            rmin, rmax = np.where(rows)[0][[0, -1]]
            cmin, cmax = np.where(cols)[0][[0, -1]]
            bh = rmax - rmin + 1
            bw = cmax - cmin + 1
            print(f"    Frame {i}: opachi={non_tr}, bbox h={bh}, w={bw}, "
                  f"y=[{rmin}-{rmax}], x=[{cmin}-{cmax}]")

    write_meta(sprite_id)
    print(f"  [OK] meta.json aggiornato")
    return True


def main():
    only_id = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only_id = sys.argv[2]

    targets = ["boss_030", "boss_031", "boss_032"]  # kraken, golem, lich
    if only_id:
        targets = [only_id]

    print("=" * 60)
    print(f"REPROCESS BOSS SPRITES (no AI regen) - targets: {targets}")
    print("=" * 60)

    ok = 0
    for bid in targets:
        if reprocess_one(bid):
            ok += 1
    print(f"\n=== Riepilogo: {ok}/{len(targets)} boss rielaborati ===")


if __name__ == "__main__":
    main()

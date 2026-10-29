#!/usr/bin/env python3
"""Task 95 — rigenerazione PixelLab dei nemici "mezzo busto" (corpo completo).

Feedback utente: "Se ci sono nemici che dovrebbero avere le gambe o le zampe
ma che sono stati disegnati come 'mezzo busto' senza le gambe, ti chiedo di
rigenerarli con pixel lab in modo da ottenere il corpo completo e non
solttanto la metà."

Audit 2026-10-30 (agente parallelo, VLM su 44 nemici + 17 boss): gli
offender sono SOLO 3 (tutti i boss sono full-body):
  - monster_007 WITCH (la strega dello screenshot utente): mezzo busto, il
    corpo finisce in vita e sotto fluttuano DUE POZIONI;
  - monster_044 LOST_SOUL: torso muscoloso SOLIDO tagliato netto in vita;
  - monster_031 GIBBERING_MOUTHER (borderline): massa di carne fluttuante
    con ~25% di vuoto sotto (nel D&D e' un blob aderente al terreno).

Pipeline = quella del bestiario esistente (gen_deterministic_walk.py) ma
con la base generata via PIXELLAB (richiesta utente) invece di z-ai:
  1. base 256x256 con pl_api.create_image_pixflux, color anchor = frame 0
     dello sheet attuale (palette coerente col personaggio);
  2. process_base_to_64x64: crop/scala, piedi ancorati a y=56, palette 16
     colori (importato da gen_deterministic_walk);
  3. compose_spritesheet_deterministic: sheet 256x64, walk-cycle sul posto
     (busto fermo, gambe alternate) — la semantica che usa Enemy.gd;
  4. write_meta + copia su mirror legacy e su godot/assets/sprites.

Costo: 3 generazioni PixelLab. Rilanciabile: la base in staging non si
rigenera se esiste gia' (per cambiare seed: cancellare out/task95_<id>/).
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

HERE = Path("/home/z/my-project/ArcadeMaze")
sys.path.insert(0, str(HERE / "scripts"))
sys.path.insert(0, str(HERE / "scripts" / "pixellab"))

import pl_api  # noqa: E402
from gen_deterministic_walk import (  # noqa: E402
    compose_spritesheet_deterministic,
    process_base_to_64x64,
    write_meta,
)
from gen_boss_animations_v2 import SPRITES_DIR  # noqa: E402  (mirror legacy)

GODOT_SPRITES = HERE / "godot" / "assets" / "sprites"
OUT_DIR = HERE / "scripts" / "pixellab" / "out"

STYLE = (
    "gothic fantasy D&D style, 16-color palette, front view, "
    "full body filling the canvas, OPAQUE body with NO transparency and "
    "NO gaps, solid flat pure black RGB(0,0,0) background, crisp pixel "
    "art outlines, NO text NO UI NO watermark"
)

OFFENDERS: dict = {
    # ---- WITCH: la strega dello screenshot utente (mezzo busto + pozioni) --
    # v2: proporzioni chunky + silhouette edge-to-edge (la v1 generava una
    # strega sottile al 40% del canvas -> sprite piccolo e magro nel frame)
    "monster_007": {
        "seed": 197,
        "description": (
            "Pixel art sprite of a swamp witch scene, a witch standing "
            "at the center with a huge pointed black hat with wide brim, "
            "glowing green skin, crooked nose with warts, tattered purple "
            "bell-shaped robe reaching the ground, holding a small potion "
            "vial raised in one hand, a small black cat sitting at her "
            "feet on the left side, a little bubbling green cauldron at "
            "her feet on the right side, the whole group composition fills "
            "the ENTIRE canvas from the left edge to the right edge and "
            "from top to bottom, hat touching the top edge, cat and "
            "cauldron touching the bottom edge, gothic fantasy D&D "
            "style, 16-color palette, front view, detailed pixel art "
            "shading, high contrast gothic lighting, OPAQUE body with NO "
            "transparency and NO gaps, solid flat pure black RGB(0,0,0) "
            "background, crisp pixel art outlines, NO text NO UI NO "
            "watermark"
        ),
        "negative_description": (
            "half body, bust, cut at the waist, no legs, floating potion "
            "bottles, empty space below, thin stick figure, slender statue, "
            "side view, sitting, text, ui, watermark"
        ),
    },
    # ---- LOST_SOUL: torso solido tagliato in vita -> figura eterea completa --
    # v2: shading dettagliato + base di nebbia a terra (v1 = silhouette
    # bianca troppo semplice, fluttuante in alto)
    "monster_044": {
        "seed": 173,
        "description": (
            "Pixel art sprite of a lost soul, tormented ghostly spirit of "
            "a fallen warrior with chunky arcade proportions, pale "
            "grey-blue ethereal body with detailed shading, ragged burial "
            "shroud with torn edges flowing down to the ground, broken "
            "chains hanging from both wrists, hollow glowing white eyes, "
            "arms reaching forward, standing on a wispy mist base that "
            "touches the bottom edge, the figure fills the ENTIRE canvas "
            "from edge to edge, gothic fantasy D&D style, 16-color palette, "
            "front view, detailed pixel art shading, high contrast gothic "
            "lighting, OPAQUE body with NO transparency and NO gaps, solid "
            "flat pure black RGB(0,0,0) background, crisp pixel art "
            "outlines, NO text NO UI NO watermark"
        ),
        "negative_description": (
            "severed torso, muscular torso cut at the waist, half body, "
            "plain flat white silhouette, no lower body, floating in air "
            "with empty space below, side view, text, ui, watermark"
        ),
    },
    # ---- GIBBERING_MOUTHER: carne fluttuante -> blob aderente al terreno ----
    # v2: corpo continuo senza buchi (v1: il flood-fill entrava nelle bocche
    # scure e scavava canali trasparenti al centro del blob)
    "monster_031": {
        "seed": 181,
        "description": (
            "Pixel art sprite of a gibbering mouther, a TALL wide dome-shaped "
            "mound of "
            "pale sickly grey-pink flesh crawling on the dungeon floor, "
            "covered in bulging yellow eyes and gaping toothy mouths drawn "
            "on its surface, dripping green ooze, continuous solid body "
            "with NO holes and NO gaps, the tall mound fills the ENTIRE "
            "canvas from the top edge to the bottom edge and from side to "
            "side, no legs, gothic "
            "fantasy D&D style, 16-color palette, front view, detailed pixel "
            "art shading, OPAQUE body, solid flat pure black RGB(0,0,0) "
            "background, crisp pixel art outlines, NO text NO UI NO "
            "watermark"
        ),
        "negative_description": (
            "floating in mid air, empty space below, holes through the "
            "body, hollow center, gaps in the flesh, legs, humanoid body, "
            "arms, side view, text, ui, watermark"
        ),
    },
}


def _close_alpha_channels(arr) -> "np.ndarray":
    """Chiusura morfologica dell'alpha (dilata->erodi) 64x64.

    Rimedi ai canali trasparenti che il flood-fill scava dentro il corpo
    quando parti scure del personaggio (bocche del mouther) sono connesse
    allo sfondo: chiusure <=2px si saldano senza cambiare la silhouette.
    """
    import numpy as np

    a = (arr[..., 3] > 0).astype(np.uint8)

    def dilate(m: np.ndarray) -> np.ndarray:
        p = np.pad(m, 1)
        return (p[:-2, :-2] | p[:-2, 1:-1] | p[:-2, 2:]
                | p[1:-1, :-2] | p[1:-1, 1:-1] | p[1:-1, 2:]
                | p[2:, :-2] | p[2:, 1:-1] | p[2:, 2:])

    def erode(m: np.ndarray) -> np.ndarray:
        p = np.pad(m, 1)
        return (p[:-2, :-2] & p[:-2, 1:-1] & p[:-2, 2:]
                & p[1:-1, :-2] & p[1:-1, 1:-1] & p[1:-1, 2:]
                & p[2:, :-2] & p[2:, 1:-1] & p[2:, 2:])

    for _ in range(2):
        a = erode(dilate(a))
    out = arr.copy()
    out[..., 3] = a * 255
    return out


def _reanchor_feet(arr) -> "np.ndarray":
    """Riporta l'ultima riga opaca a y=56 se il threshold dell'alpha ha
    mangiato i piedi (v1: punte di veste/emibusto semitrasparenti tagliate
    a y52 con 12px di vuoto sotto)."""
    import numpy as np

    a = arr[..., 3] > 0
    rows = np.where(a.any(axis=1))[0]
    if rows.size == 0:
        return arr
    last = int(rows.max())
    shift = 56 - last
    if 0 < shift <= 12:
        out = np.zeros_like(arr)
        h = arr.shape[0]
        out[shift:h, :, :] = arr[0:h - shift, :, :]
        return out
    return arr


def _drop_stray_bits(arr, min_px: int = 24) -> "np.ndarray":
    """Rimuove i componenti connessi isolati < min_px (gocce/frammenti
    staccati dal corpo: v3 del mouther aveva una goccia di 12px separata
    dalla massa con un vuoto di 4 righe)."""
    import numpy as np
    from collections import deque

    a = arr[..., 3] > 0
    seen = np.zeros_like(a, dtype=bool)
    keep = np.zeros_like(a, dtype=bool)
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            if a[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                px = [(y, x)]
                while q:
                    cy, cx = q.popleft()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if (0 <= ny < a.shape[0] and 0 <= nx < a.shape[1]
                                        and a[ny, nx] and not seen[ny, nx]):
                            seen[ny, nx] = True
                            q.append((ny, nx))
                            px.append((ny, nx))
                if len(px) >= min_px:
                    for (py, pxx) in px:
                        keep[py, pxx] = True
    out = arr.copy()
    out[..., 3] = np.where(keep, arr[..., 3], 0)
    return out


def regen(entity_id: str, spec: dict) -> bool:
    print(f"\n[95] {entity_id} — {spec.get('label', '')}")
    out_dir = OUT_DIR / f"task95_{entity_id}"
    out_dir.mkdir(parents=True, exist_ok=True)

    godot_sheet = GODOT_SPRITES / f"{entity_id}_sheet.png"
    legacy_sheet = SPRITES_DIR / f"{entity_id}_sheet.png"

    # confronto: conserva il vecchio sheet E IL VECCHIO META nello staging
    # (il meta contiene campi custom oltre allo standard: facesLeft!)
    if godot_sheet.exists():
        old_copy = out_dir / "OLD_sheet.png"
        if not old_copy.exists():
            shutil.copy(godot_sheet, old_copy)
    old_meta_g = GODOT_SPRITES / f"{entity_id}_meta.json"
    if old_meta_g.exists():
        old_meta_copy = out_dir / "OLD_meta.json"
        if not old_meta_copy.exists():
            shutil.copy(old_meta_g, old_meta_copy)

    # 1) base PixelLab (color anchor = frame 0 dello sheet attuale)
    base_raw = out_dir / "base_raw.png"
    anchor = out_dir / "anchor.png"
    if godot_sheet.exists():
        Image.open(godot_sheet).crop((0, 0, 64, 64)).save(anchor)
    if not base_raw.exists():
        imgs = pl_api.create_image_pixflux(
            description=spec["description"],
            width=256, height=256,
            color_image_path=str(anchor) if anchor.exists() else None,
            seed=spec["seed"],
            no_background=True,
            outline="single color black outline",
            shading="basic shading",
            detail="medium detail",
            negative_description=spec["negative_description"],
            raw_dump_path=str(out_dir / "raw_pixflux.json"),
        )
        pl_api.save_b64_image(imgs[0], str(base_raw))
        print(f"  base generata (seed {spec['seed']})")
    else:
        print("  base gia' in staging — skip POST")

    # 2) post-processing -> sprite 64x64 (piedi a y=56, palette 16 colori)
    base_frame = process_base_to_64x64(base_raw)
    if base_frame is None:
        print("  ERRORE: post-processing base fallito")
        return False

    # 2b) TASK 95 v2/v3: frantumi isolati via, chiusura dei canali
    # trasparenti interni, piedi ri-ancorati a y=56 (lezioni run v1/v3:
    # flood-fill nelle bocche scure, threshold che taglia i piedi, gocce
    # staccate dal corpo)
    base_frame = _drop_stray_bits(base_frame)
    base_frame = _close_alpha_channels(base_frame)
    base_frame = _reanchor_feet(base_frame)

    # 3) sheet walk deterministico (scrive nel mirror legacy)
    compose_spritesheet_deterministic(base_frame, legacy_sheet)
    write_meta(entity_id)

    # 3b) FIX (regressione test_task51_facing): write_meta riscrive il meta
    # SENZA i campi custom del bestiario (facesLeft = sprite disegnato che
    # guarda a sinistra, usato dal flip di Enemy). Ripristina i campi
    # extra del vecchio meta sopra quello nuovo standard.
    old_meta_copy = out_dir / "OLD_meta.json"
    if old_meta_copy.exists():
        import json
        try:
            old_m: dict = json.loads(old_meta_copy.read_text(encoding="utf-8"))
        except Exception:
            old_m = {}
        for meta_path in [GODOT_SPRITES / f"{entity_id}_meta.json",
                        SPRITES_DIR / f"{entity_id}_meta.json"]:
            if meta_path.exists():
                try:
                    new_m: dict = json.loads(meta_path.read_text(encoding="utf-8"))
                except Exception:
                    continue
                changed = False
                for k, v in old_m.items():
                    if k not in new_m and k != "animations":
                        new_m[k] = v
                        changed = True
                if changed:
                    meta_path.write_text(
                        json.dumps(new_m, indent=2) + "\n", encoding="utf-8")
                    print(f"  meta: ripristinati campi custom {[k for k in old_m if k not in new_m and k != 'animations']}" if changed else "")

    # 4) copia su godot (il gioco carica da qui)
    shutil.copy(legacy_sheet, godot_sheet)
    shutil.copy(SPRITES_DIR / f"{entity_id}_meta.json",
                GODOT_SPRITES / f"{entity_id}_meta.json")

    # 5) QA pixel: corpo completo (banda centrale in basso opaca) + copertura
    sheet = Image.open(godot_sheet).convert("RGBA")
    f0 = sheet.crop((0, 0, 64, 64))
    opaque = sum(1 for p in f0.getdata() if p[3] > 128)
    band = sum(1 for y in range(48, 57) for x in range(16, 49)
               if f0.getpixel((x, y))[3] > 128)
    last_row = max((y for y in range(64) for x in range(0, 64, 2)
                    if f0.getpixel((x, y))[3] > 128), default=-1)
    print(f"  QA: copertura frame0 {opaque / 4096 * 100:.0f}%, "
          f"banda bassa centrale {band / (9 * 33) * 100:.0f}%, "
          f"ultima riga opaca y={last_row}")
    print(f"  -> {godot_sheet}")
    return True


def main() -> int:
    ids = sys.argv[1:] or list(OFFENDERS.keys())
    cost = len(ids)
    bal = pl_api.budget_guard(cost, action=f"task95 nemici x{cost}")
    print(f"[budget] balance {bal} — costo {cost}")
    failed = []
    for eid in ids:
        if eid not in OFFENDERS:
            print(f"[95] {eid} sconosciuto (validi: {list(OFFENDERS.keys())})")
            failed.append(eid)
            continue
        if not regen(eid, OFFENDERS[eid]):
            failed.append(eid)
    print("\n" + "=" * 60)
    print(f"Task 95: {len(ids) - len(failed)}/{len(ids)} rigenerati")
    if failed:
        print(f"Falliti: {', '.join(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

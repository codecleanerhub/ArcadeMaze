#!/usr/bin/env python3
"""Runner TASK 108 — genera i 5 asset dello shop (4 statici + 1 background).

Uso:
  python3 gen_task108.py            # genera tutto ciò che manca (resume)
  python3 gen_task108.py balance    # solo saldo

Flusso per statico (ricetta pl_run.run_static): pixflux 256 con anchor
eventuale -> pulizia sfondo -> QA pl_qa -> write_static (NEAREST).
Flusso per il background: pixflux 448x256 SENZA trasparenza -> QA leggera
(dim/nonblank) -> upscale NEAREST x3 -> backgrounds/bg_shop.png.

Stato per-entity in state/{id}.json: MAI ripagare un POST completato.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import defs_task108
import pl_api
import pl_integrate
import pl_qa
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(HERE, "state")
OUT_DIR = os.path.join(HERE, "out")

COST = len(defs_task108.ENTITIES) + 1  # 4 statici + 1 bg


def state_path(entity_id: str) -> str:
    return os.path.join(STATE_DIR, f"{entity_id}.json")


def load_state(entity_id: str) -> dict:
    p = state_path(entity_id)
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_state(entity_id: str, st: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(state_path(entity_id), "w", encoding="utf-8") as f:
        json.dump(st, f, indent=2)


def stage_out(entity_id: str, name: str) -> str:
    d = os.path.join(OUT_DIR, entity_id)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, name)


def run_static(entity_id: str) -> bool:
    d = defs_task108.ENTITIES[entity_id]
    target_abs = os.path.join(pl_integrate.GODOT_SPRITES, d["target"])
    st = load_state(entity_id)
    if st.get("stage") == "done" and os.path.isfile(target_abs):
        print(f"[{entity_id}] gia' completato — skip")
        return True
    base_png = stage_out(entity_id, "base.png")
    if st.get("stage") == "base_done" and os.path.isfile(base_png):
        print(f"[{entity_id}] base gia' generata — skip POST")
    else:
        imgs = pl_api.create_image_pixflux(
            description=d["description"],
            width=256, height=256,
            seed=d.get("seed", 11),
            no_background=True,
            outline=d.get("outline", "single color black outline"),
            shading=d.get("shading", "basic shading"),
            detail=d.get("detail", "medium detail"),
            view=d.get("view"),
            negative_description=d.get("negative_description"),
            raw_dump_path=stage_out(entity_id, "raw_pixflux.json"),
        )
        pl_api.save_b64_image(imgs[0], base_png)
        st["stage"] = "base_done"
        save_state(entity_id, st)
    # pulizia locale gratuita
    clean_png = stage_out(entity_id, "clean.png")
    img = Image.open(base_png).convert("RGBA")
    img = pl_integrate.remove_solid_background(img, tol=26)
    n_cols = len({(p[0], p[1], p[2]) for p in img.getdata() if p[3] > 0})
    if n_cols > 96:
        img = pl_integrate.reduce_palette(img, 96)
    img.save(clean_png, "PNG")
    # QA
    errors = pl_qa.qa_static(img, ref=None, max_colors=96, cov=(8.0, 60.0))
    if not pl_qa.report(entity_id + " [static]", errors):
        print(f"[{entity_id}] QA FALLITA — clean in {clean_png}, NON integrata")
        return False
    final = pl_integrate.write_static(d["target"], img, tuple(d.get("size", (128, 128))))
    st["stage"] = "done"
    st["output"] = final
    save_state(entity_id, st)
    print(f"[{entity_id}] integrato -> {final}")
    return True


def run_bg() -> bool:
    d = defs_task108.BG_SHOP
    target = d["target"]
    st = load_state(d["id"])
    if st.get("stage") == "done" and os.path.isfile(target):
        print(f"[{d['id']}] gia' completato — skip")
        return True
    base_png = stage_out(d["id"], "base.png")
    if st.get("stage") == "base_done" and os.path.isfile(base_png):
        print(f"[{d['id']}] base gia' generata — skip POST")
    else:
        imgs = pl_api.create_image_pixflux(
            description=d["description"],
            width=d["gen_size"][0], height=d["gen_size"][1],
            seed=d["seed"],
            no_background=False,  # scena piena, niente trasparenza
            outline="single color black outline",
            shading="basic shading",
            detail="medium detail",
            negative_description=d["negative_description"],
            raw_dump_path=stage_out(d["id"], "raw_pixflux.json"),
        )
        pl_api.save_b64_image(imgs[0], base_png)
        st["stage"] = "base_done"
        save_state(d["id"], st)
    img = Image.open(base_png).convert("RGBA")
    # QA leggera: dimensioni giuste e immagine non vuota/colori presenti
    errors: list[str] = []
    if img.size != tuple(d["gen_size"]):
        errors.append(f"dimensioni {img.size} attese {d['gen_size']}")
    opaque = sum(1 for p in img.getdata() if p[3] > 200)
    if opaque < d["gen_size"][0] * d["gen_size"][1] * 0.5:
        errors.append("immagine semitrasparente/vuota")
    if not pl_qa.report(d["id"] + " [bg]", errors):
        print(f"[{d['id']}] QA FALLITA — base in {base_png}, NON integrata")
        return False
    # upscale NEAREST x3 -> 1344x768 (integer, pixel art pulita)
    up = img.resize(tuple(d["final_size"]), Image.NEAREST)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.isfile(target):  # backup una volta sola
        bak = target + ".bak-pre-pixellab-v2"
        if not os.path.isfile(bak):
            import shutil
            shutil.copy2(target, bak)
    up.save(target, "PNG")
    st["stage"] = "done"
    st["output"] = target
    save_state(d["id"], st)
    print(f"[{d['id']}] integrato -> {target} ({d['final_size']})")
    return True


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "balance":
        print(f"generazioni residue: {pl_api.get_balance()}")
        return
    bal = pl_api.budget_guard(COST, "task108-shop")
    print(f"[task108] saldo {bal}, costo previsto {COST}")
    ok = True
    for eid in defs_task108.ENTITIES:
        ok = run_static(eid) and ok
    ok = run_bg() and ok
    print("[task108] ESITO:", "TUTTI GLI ASSET OK" if ok else "CON ERRORI (vedi sopra)")


if __name__ == "__main__":
    main()

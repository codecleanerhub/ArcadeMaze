#!/usr/bin/env python3
"""Runner pipeline PixelLab v2 — ricette statico e animato (§8.2).

Uso:
  python3 pl_run.py balance
  python3 pl_run.py static  defs_items item_chalice [id2 ...]
  python3 pl_run.py anim    defs_scenery torch [id2 ...]

Costi: statico = 1 generazione; animato = 5 (1 base + 4 frame).
Stato per-entity in state/{id}.json: riprende senza ripagare POST completati.
Prima di ogni batch: budget guard (balance - costo >= MIN_RESERVE).

Le definizioni vivono nei moduli defs_*.py con formato:
  ENTITIES = {
    "<id>": {
      "kind": "static" | "anim",
      "target": "<percorso relativo a godot/assets/sprites>",
      "size": (w, h),              # canvas finale statico
      "description": "...",        # prompt pixflux (Body/Pose/Palette blocks)
      # solo anim:
      "action": "...",             # testo azione animate-v3
      "frame_count": 4,            # default 4
      # opzionali (API pixflux): outline, shading, detail, view, direction,
      # negative_description, color_image (default: file target se esiste),
      "quantize": True,            # default False per statici legacy smooth
    },
  }
"""
from __future__ import annotations

import importlib
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pl_api
import pl_integrate
import pl_qa
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(HERE, "state")
OUT_DIR = os.path.join(HERE, "out")  # staging: basi e frame grezzi

STATIC_COST = 1
ANIM_COST = 5  # 1 base + 4 frame


# ---------------------------------------------------------------- stato

def state_path(entity_id: str) -> str:
    return os.path.join(STATE_DIR, f"{entity_id}.json")


def load_state(entity_id: str) -> dict:
    p = state_path(entity_id)
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_state(entity_id: str, state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(state_path(entity_id), "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def stage_out(entity_id: str, name: str) -> str:
    d = os.path.join(OUT_DIR, entity_id)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, name)


def _color_anchor_png(entity_id: str, color_image: str | None,
                      target_abs: str) -> str | None:
    """Prepara il color_image: file esplicito oppure il target originale.
    Viene portato a 256x256 (canvas centrato) come da ricetta validata."""
    src = color_image
    if src is None and os.path.isfile(target_abs):
        src = target_abs
    if src is None:
        return None
    img = Image.open(src).convert("RGBA")
    if img.size != (256, 256):
        canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        img.thumbnail((256, 256), Image.LANCZOS)
        canvas.paste(img, ((256 - img.size[0]) // 2, (256 - img.size[1]) // 2), img)
        out = stage_out(entity_id, "anchor.png")
        canvas.save(out, "PNG")
        return out
    return src


# ---------------------------------------------------------------- ricette

def run_static(defs: dict, entity_id: str, skip_qa_exit: bool = True) -> bool:
    """Ricetta statico: pixflux 256 con color_image -> QA -> integra."""
    d = defs[entity_id]
    target_abs = os.path.join(pl_integrate.GODOT_SPRITES, d["target"])
    st = load_state(entity_id)

    if st.get("stage") == "done" and os.path.isfile(target_abs):
        print(f"[{entity_id}] già completato — skip (mai ripagare)")
        return True

    # 1) base pixflux (SYNC, 1 gen) — con resume
    base_png = stage_out(entity_id, "base.png")
    if st.get("stage") == "base_done" and os.path.isfile(base_png):
        print(f"[{entity_id}] base già generata — skip POST")
    else:
        anchor = _color_anchor_png(entity_id, d.get("color_image"), target_abs)
        imgs = pl_api.create_image_pixflux(
            description=d["description"],
            width=256, height=256,
            color_image_path=anchor,
            seed=d.get("seed", 11),
            no_background=True,
            outline=d.get("outline", "single color black outline"),
            shading=d.get("shading", "basic shading"),
            detail=d.get("detail", "medium detail"),
            view=d.get("view", "side"),
            direction=d.get("direction"),
            negative_description=d.get("negative_description"),
        )
        pl_api.save_b64_image(imgs[0], base_png)
        st["stage"] = "base_done"
        st["base_file"] = base_png
        save_state(entity_id, st)

    # 2) QA (reference = originale se esiste)
    img = Image.open(base_png)
    ref = Image.open(target_abs) if os.path.isfile(target_abs) else None
    errors = pl_qa.qa_static(img, ref=ref,
                             max_colors=d.get("max_colors", 96),
                             cov=d.get("coverage", (8.0, 60.0)))
    ok = pl_qa.report(entity_id + " [static]", errors)
    if not ok:
        print(f"[{entity_id}] QA FALLITA — base in {base_png}, NON integrata")
        return False

    # 3) integrazione
    final = pl_integrate.write_static(d["target"], img, tuple(d.get("size", (128, 128))))
    st["stage"] = "done"
    st["output"] = final
    save_state(entity_id, st)
    print(f"[{entity_id}] integrato -> {final}")
    return True


def run_anim(defs: dict, entity_id: str) -> bool:
    """Ricetta animato: base pixflux -> animate v3 (4 frame) -> QA -> sheet."""
    d = defs[entity_id]
    target_abs = os.path.join(pl_integrate.GODOT_SPRITES, d["target"])
    st = load_state(entity_id)

    if st.get("stage") == "done" and os.path.isfile(target_abs):
        print(f"[{entity_id}] già completato — skip")
        return True

    # 1) base (1 gen)
    base_png = stage_out(entity_id, "base.png")
    if st.get("stage") in ("base_done", "anim_submitted") and os.path.isfile(base_png):
        print(f"[{entity_id}] base già generata — skip POST")
    else:
        anchor = _color_anchor_png(entity_id, d.get("color_image"), target_abs)
        imgs = pl_api.create_image_pixflux(
            description=d["description"],
            width=256, height=256,
            color_image_path=anchor,
            seed=d.get("seed", 11),
            no_background=True,
            outline=d.get("outline", "single color black outline"),
            shading=d.get("shading", "basic shading"),
            detail=d.get("detail", "medium detail"),
            view=d.get("view", "side"),
            direction=d.get("direction"),
            negative_description=d.get("negative_description"),
        )
        pl_api.save_b64_image(imgs[0], base_png)
        st["stage"] = "base_done"
        st["base_file"] = base_png
        save_state(entity_id, st)

    # 2) animate v3 (4 gen) — discard prima immagine (reference)
    frames_dir = stage_out(entity_id, "frames")
    if st.get("stage") == "anim_submitted" and os.path.isdir(frames_dir) and \
            len([f for f in os.listdir(frames_dir) if f.endswith(".png")]) >= 4:
        print(f"[{entity_id}] frame già scaricati — skip POST")
        st["stage"] = "frames_done"
        save_state(entity_id, st)
    if st.get("stage") == "base_done":
        raw = pl_api.animate_with_text_v3(
            first_frame_path=base_png,
            action=d["action"],
            frame_count=d.get("frame_count", 4),
            seed=d.get("anim_seed", 7),
        )
        # la PRIMA immagine è il reference: scartala (§8.2 passo 3)
        payload_imgs = raw[1:] if len(raw) > d.get("frame_count", 4) else raw
        os.makedirs(frames_dir, exist_ok=True)
        for i, b64 in enumerate(payload_imgs[: d.get("frame_count", 4)]):
            pl_api.save_b64_image(b64, os.path.join(frames_dir, f"f{i}.png"))
        st["stage"] = "frames_done"
        st["frame_count"] = len(payload_imgs)
        save_state(entity_id, st)

    # 3) QA frame
    frames = [Image.open(os.path.join(frames_dir, f"f{i}.png"))
              for i in range(d.get("frame_count", 4))
              if os.path.isfile(os.path.join(frames_dir, f"f{i}.png"))]
    if len(frames) < d.get("frame_count", 4):
        print(f"[{entity_id}] frame insufficienti ({len(frames)}) — rilanciare")
        return False
    ref = Image.open(target_abs) if os.path.isfile(target_abs) else None
    errors = pl_qa.qa_anim_frames(frames, ref=ref, feet_check=d.get("feet_check", False))
    ok = pl_qa.report(entity_id + " [anim]", errors)
    if not ok:
        print(f"[{entity_id}] QA FALLITA — frame in {frames_dir}, NON integrati")
        return False

    # 4) sheet 256x64 + meta
    final = pl_integrate.write_anim_sheet(
        d["target"], frames,
        frame_px=d.get("frame_px", 64),
        feet_y=d.get("feet_y", 56),
        anchor=tuple(d.get("anchor", (32, 56))),
    )
    st["stage"] = "done"
    st["output"] = final
    save_state(entity_id, st)
    print(f"[{entity_id}] sheet integrato -> {final}")
    return True


# ---------------------------------------------------------------- main

def load_defs(module_name: str) -> dict:
    mod = importlib.import_module(module_name)
    return getattr(mod, "ENTITIES")


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] == "balance":
        print(f"generazioni residue: {pl_api.get_balance()}")
        return
    cmd = args[0]
    if cmd not in ("static", "anim"):
        raise SystemExit(__doc__)
    defs = load_defs(args[1])
    ids = args[2:]
    if not ids:
        ids = list(defs.keys())
    cost = len(ids) * (STATIC_COST if cmd == "static" else ANIM_COST)
    bal = pl_api.budget_guard(cost, action=f"{cmd} x{len(ids)}")
    print(f"[budget] balance {bal} — batch {len(ids)} entity, costo ~{cost}")
    ok_all = True
    for i, eid in enumerate(ids):
        if eid not in defs:
            print(f"[{eid}] SCONOSCIUTO in {args[1]}")
            ok_all = False
            continue
        try:
            ok = run_static(defs, eid) if cmd == "static" else run_anim(defs, eid)
            ok_all = ok_all and ok
        except Exception as e:  # noqa: BLE001 — logga e continua col batch
            print(f"[{eid}] ERRORE: {e}")
            ok_all = False
        if i < len(ids) - 1:
            time.sleep(3.0)  # pace tra POST
    print(f"[batch] {'COMPLETO' if ok_all else 'CON ERRORI'} — "
          f"balance residuo ~{pl_api.get_balance():.2f}")
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()

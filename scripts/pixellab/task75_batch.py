#!/usr/bin/env python3
"""task75_batch.py — TASK 75: animazioni WALK dei player via animate-v3
dal frame 0 ESISTENTE (lezione Task 74: il first_frame preserva il look,
cambiano SOLO le pose) + pietrificazione della statua UNICORNO.

Diagnosi VLM (task75_walk_compare_all.png): 5 personaggi su 9 NON hanno
un walk cycle leggibile (mage, orc, golem, dragon, vampire — sheet con 4
frame quasi identici). Matrice base|armored:
  player1 WALK|STATIC   player2 WALK|STATIC   mage STATIC|WALK
  orc STATIC|STATIC     elf WALK|WALK         knight WALK|WALK
  golem STATIC|STATIC   dragon STATIC|STATIC   vampire STATIC|STATIC
=> 5 job walk base (mage, orc, golem, dragon, vampire) + 6 job armored
(player1, player2, orc, golem, dragon, vampire) + 1 job statua unicorno
= 12 job @ 1 credito = 12 crediti (saldo 385.75).

Uso:
  python3 task75_batch.py submit   # invia TUTTI i job (paralleli lato server)
  python3 task75_batch.py poll      # poll di tutti i job non done, salva raw
  python3 task75_batch.py status    # stato
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image

import pl_api

STATE = os.path.join(HERE, "state", "task75_jobs.json")
OUT = os.path.join(HERE, "out", "task75")

SPR = "/home/z/my-project/ArcadeMaze/godot/assets/sprites"

WALK_TAIL = (
    ", each frame a clearly different leg pose, silhouette changes every "
    "frame, no camera movement, no color drift, background stays transparent"
)

ENTITIES: dict = {
    # ---- 1) statua UNICORNO: pietrificazione del frame 0 (il piu' statuario:
    # gambe raccolte, postura fiera — VLM task75_unicorn_frames) ------------
    "unicorn_statue": {
        "src": f"{SPR}/unicorn_ally_sheet.png",
        "action": (
            "the proud unicorn slowly petrifies into an ancient stone "
            "statue: all colors drain away into weathered gray stone, "
            "fine cracks spread across the pearl white flanks, the flowing "
            "mane and tail stiffen into solid carved rock, the golden horn "
            "turns to carved gray stone with chipped edges, the hooves lock "
            "to the ground, the pose freezes completely, subtle moss appears "
            "on the hooves, no movement, no camera movement, background "
            "stays transparent"
        ),
        "seed": 75,
    },
    # ---- 2) walk BASE (SD frame 0 -> 256) -----------------------------------
    "walk_mage": {
        "src": f"{SPR}/char_mage_sheet.png",
        "action": (
            "the wizard walks forward in a steady walk cycle: legs "
            "alternating clearly beneath the long robe, one foot stepping "
            "forward while the other pushes back, robe hem swaying with "
            "each step, arms swinging with the stride, staff held steady, "
            "hat and beard bobbing slightly" + WALK_TAIL
        ),
        "seed": 76,
    },
    "walk_orc": {
        "src": f"{SPR}/char_orc_sheet.png",
        "action": (
            "the orc warrior walks forward in a heavy confident walk cycle: "
            "muscular legs alternating clearly, one leg stepping forward "
            "while the other pushes back, arms swinging with the stride, "
            "shoulder plates shifting, jaw and tusks steady" + WALK_TAIL
        ),
        "seed": 77,
    },
    "walk_golem": {
        "src": f"{SPR}/char_golem_sheet.png",
        "action": (
            "the stone golem walks forward in a slow heavy walk cycle: "
            "massive rocky legs alternating clearly, one leg stepping "
            "forward while the other pushes back, arms swinging with the "
            "stride, rocky body leaning slightly into each step, glowing "
            "chest crystal steady" + WALK_TAIL
        ),
        "seed": 78,
    },
    "walk_dragon": {
        "src": f"{SPR}/char_dragon_sheet.png",
        "action": (
            "the small dragon walks forward in a lively walk cycle: legs "
            "alternating clearly, one leg stepping forward while the other "
            "pushes back, tail swaying with each stride, small wings "
            "folding and unfolding slightly, body bobbing gently" + WALK_TAIL
        ),
        "seed": 79,
    },
    "walk_vampire": {
        "src": f"{SPR}/char_vampire_sheet.png",
        "action": (
            "the vampire walks forward in an elegant prowling walk cycle: "
            "legs alternating clearly, one leg stepping forward while the "
            "other pushes back, long cape billowing and swaying with each "
            "stride, arms swinging with dignity, high collar steady"
            + WALK_TAIL
        ),
        "seed": 80,
    },
    # ---- 3) walk ARMORED (XHD frame 0 nativo 256) ---------------------------
    "arm_player1": {
        "src": f"{SPR}/xhd/player1_armored_xhd_sheet.png",
        "action": (
            "the armored hero walks forward in a steady walk cycle: armored "
            "legs alternating clearly, one boot stepping forward while the "
            "other pushes back, arms swinging with the stride, full plate "
            "armor shifting with each step, sword held steady" + WALK_TAIL
        ),
        "seed": 81,
    },
    "arm_player2": {
        "src": f"{SPR}/xhd/player2_armored_xhd_sheet.png",
        "action": (
            "the armored heroine walks forward in a steady walk cycle: "
            "armored legs alternating clearly, one boot stepping forward "
            "while the other pushes back, arms swinging with the stride, "
            "full plate armor shifting with each step, hair swaying"
            + WALK_TAIL
        ),
        "seed": 82,
    },
    "arm_orc": {
        "src": f"{SPR}/xhd/char_orc_armored_xhd_sheet.png",
        "action": (
            "the armored orc warrior walks forward in a heavy walk cycle: "
            "armored legs alternating clearly, one boot stepping forward "
            "while the other pushes back, arms swinging with the stride, "
            "plate armor plates shifting with each step" + WALK_TAIL
        ),
        "seed": 83,
    },
    "arm_golem": {
        "src": f"{SPR}/xhd/char_golem_armored_xhd_sheet.png",
        "action": (
            "the armored stone golem walks forward in a slow heavy walk "
            "cycle: massive legs alternating clearly, one foot stepping "
            "forward while the other pushes back, arms swinging with the "
            "stride, metal plates over the rocky body shifting with each "
            "step" + WALK_TAIL
        ),
        "seed": 84,
    },
    "arm_dragon": {
        "src": f"{SPR}/xhd/char_dragon_armored_xhd_sheet.png",
        "action": (
            "the armored dragon walks forward in a lively walk cycle: legs "
            "alternating clearly, one leg stepping forward while the other "
            "pushes back, tail swaying with each stride, armored scales "
            "shifting with each step" + WALK_TAIL
        ),
        "seed": 85,
    },
    "arm_vampire": {
        "src": f"{SPR}/xhd/char_vampire_armored_xhd_sheet.png",
        "action": (
            "the armored vampire walks forward in an elegant prowling walk "
            "cycle: armored legs alternating clearly, one boot stepping "
            "forward while the other pushes back, long cape billowing "
            "with each stride, arms swinging with dignity" + WALK_TAIL
        ),
        "seed": 86,
    },
}

FRAME_PX_SRC = 64 if True else 256  # aggiornato sotto in base a src


def build_first_frame(entity: str, spec: dict) -> str:
    """Frame 0 dello sheet sorgente su canvas 256x256 (NEAREST se SD)."""
    out_dir = os.path.join(OUT, entity)
    os.makedirs(out_dir, exist_ok=True)
    out_f = os.path.join(out_dir, "first.png")
    im = Image.open(spec["src"]).convert("RGBA")
    fw = im.width // 4
    frame = im.crop((0, 0, fw, fw))
    if fw != 256:
        frame = frame.resize((256, 256), Image.NEAREST)
    frame.save(out_f)
    return out_f


def load_state() -> dict:
    if os.path.isfile(STATE):
        with open(STATE) as f:
            return json.load(f)
    return {}


def save_state(st: dict) -> None:
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(st, f, indent=2)


def cmd_submit() -> None:
    st = load_state()
    planned = sum(1 for e in ENTITIES if e not in st or not st[e].get("job_id"))
    bal = pl_api.budget_guard(planned, "task75-batch")
    print(f"[budget] balance {bal} — job nuovi: {planned}")
    for entity, spec in ENTITIES.items():
        if st.get(entity, {}).get("job_id"):
            print(f"[skip] {entity}: job {st[entity]['job_id']} gia' inviato")
            continue
        ff = build_first_frame(entity, spec)
        job_id = pl_api.submit_animate_with_text_v3(
            first_frame_path=ff, action=spec["action"],
            frame_count=4, seed=spec["seed"])
        st[entity] = {"job_id": job_id, "done": False}
        save_state(st)  # persistito SUBITO (anti-doppio-POST, lezione Task 74)
        print(f"[submit] {entity} -> {job_id}")


def cmd_poll() -> None:
    st = load_state()
    for entity, spec in ENTITIES.items():
        rec = st.get(entity, {})
        if not rec.get("job_id"):
            print(f"[skip] {entity}: mai inviato")
            continue
        raw_dir = os.path.join(OUT, entity, "raw")
        if rec.get("done") and os.path.isdir(raw_dir) and \
                        len(os.listdir(raw_dir)) >= 4:
            print(f"[ok] {entity}: gia' scaricato")
            continue
        try:
            raw = pl_api.poll_background_job(rec["job_id"])
        except Exception as exc:  # noqa: BLE001 — un fallimento non ferma il batch
            print(f"[FAIL] {entity}: {exc}")
            continue
        os.makedirs(raw_dir, exist_ok=True)
        for i, b64 in enumerate(raw):
            pl_api.save_b64_image(b64, os.path.join(raw_dir, f"r{i}.png"))
        rec["done"] = True
        rec["n_raw"] = len(raw)
        save_state(st)
        print(f"[done] {entity}: {len(raw)} immagini raw -> {raw_dir}")


def cmd_status() -> None:
    st = load_state()
    for entity in ENTITIES:
        rec = st.get(entity, {})
        raw_dir = os.path.join(OUT, entity, "raw")
        n = len(os.listdir(raw_dir)) if os.path.isdir(raw_dir) else 0
        print(f"  {entity:16s} job={rec.get('job_id', '-'):38s} "
              f"done={rec.get('done', False)} raw={n}")


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "submit":
        cmd_submit()
    elif cmd == "poll":
        cmd_poll()
    else:
        cmd_status()


if __name__ == "__main__":
    main()

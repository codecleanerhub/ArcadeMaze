## gen_xhd_assets.py - Genera gli sheet XHD 4x (Task 22) per PLAYER e BOSS.
## Deterministico: stessi input -> stessi output byte per byte.
## Output: godot/assets/sprites/xhd/<id>_xhd_sheet.png
## Gli originali NON vengono mai toccati (rollback = cancellare xhd/).
## Riga di comando: --only players|bosses|all (default all)
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from upscale_xhd_lib import upscale_sheet

SPR = "/home/z/my-project/ArcadeMaze/godot/assets/sprites"
DST = os.path.join(SPR, "xhd")

PLAYER_BASES = [
    "player1", "player2", "char_mage", "char_orc", "char_elf",
    "char_knight", "char_golem", "char_dragon", "char_vampire",
]
BOSS_IDS = [f"boss_{i:03d}" for i in range(21, 38)]  # 021..037


def build_jobs(which: str):
    jobs = []  # (src_file, id)
    if which in ("players", "all"):
        for b in PLAYER_BASES:
            jobs.append((f"{b}_sheet.png", b))
            for i in range(4):
                jobs.append((f"{b}_walk{i}_sheet.png", f"{b}_walk{i}"))
            jobs.append((f"{b}_jump_sheet.png", f"{b}_jump"))
    if which in ("bosses", "all"):
        for bid in BOSS_IDS:
            jobs.append((f"{bid}_sheet.png", bid))
    return jobs


def main() -> int:
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which not in ("players", "bosses", "all"):
        print("usage: gen_xhd_assets.py [players|bosses|all]")
        return 2
    os.makedirs(DST, exist_ok=True)
    jobs = build_jobs(which)
    t0 = time.time()
    ok, skip, fail = 0, 0, 0
    for src_file, sid in jobs:
        src = os.path.join(SPR, src_file)
        dst = os.path.join(DST, f"{sid}_xhd_sheet.png")
        if not os.path.exists(src):
            print(f"  SKIP (missing src) {src_file}")
            skip += 1
            continue
        try:
            n_frames, size = upscale_sheet(src, dst)
            ok += 1
            print(f"  OK {sid}_xhd_sheet.png  frames={n_frames} size={size[0]}x{size[1]}")
        except Exception as e:
            print(f"  FAIL {src_file}: {e}")
            fail += 1
    total_kb = sum(os.path.getsize(os.path.join(DST, f)) for f in os.listdir(DST) if f.endswith(".png")) // 1024
    print(f"\nDone in {time.time()-t0:.1f}s: ok={ok} skip={skip} fail={fail} | xhd/ total = {total_kb} KB ({len(os.listdir(DST))} files)")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

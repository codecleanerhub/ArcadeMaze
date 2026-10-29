#!/usr/bin/env python3
"""Task 98 — calcoli per il report sulle meccaniche punti (dati reali dal codice).

Estrae: HP base per tipo nemico (Enemy.gd STATS), spawner counts, boss/miniboss
indici, e calcola: valore medio nemico, massimo cumulabile min/max, curva XP
proposta (1000 x n^1.75 arrotondata a 50), tabella soglie, punti abilita'.
Output JSON per lo script del PDF.
"""
import json
import re

SRC = "/home/z/my-project/ArcadeMaze/godot/scripts/enemies/Enemy.gd"
s = open(SRC, encoding="utf-8").read()

# estrai STATS: EnemyType.X: {"speed": n, "health": h, ...}
stats = {}
for m in re.finditer(r'EnemyType\.(\w+):\s*\{([^}]+)\}', s):
    name = m.group(1)
    hm = re.search(r'"health":\s*(\d+)', m.group(2))
    if hm:
        stats[name] = int(hm.group(1))
print(f"tipi con HP: {len(stats)}")

ORIG = 28  # EnemyType.ENEMY_ORIGINAL_TYPE_COUNT
PTS_PER_HP = 10
vals = {k: v * PTS_PER_HP for k, v in stats.items()}
orig_vals = list(vals.values())[:ORIG]
all_vals = list(vals.values())

avg_orig = sum(orig_vals) / len(orig_vals)
avg_all = sum(all_vals) / len(all_vals)
print(f"valore nemico: min {min(all_vals)} max {max(all_vals)} "
      f"media originali {avg_orig:.1f} media tutti {avg_all:.1f}")

# --- spawn: 51 livelli maze, wave 6 + (L-1)/4, respawn 100% -> x2 ---
maze_levels = [l for l in range(1, 69) if l % 4 != 0]
assert len(maze_levels) == 51
kills = sum((6 + (l - 1) // 4) * 2 for l in maze_levels)
print(f"nemici uccidibili totali (respawn 100%): {kills}")

# --- mini-boss: 1 per livello maze, tipo = (L-1) % 51 ---
mb_types = [(l - 1) % 51 for l in maze_levels]
mb_total = sum(300 + 15 * t for t in mb_types)
print(f"mini-boss: {len(mb_types)}, totale {mb_total}")

# --- boss: livelli 4,8,...,68; punti = 2500 + 100 x ((L/4)%17) ---
boss_levels = [l for l in range(4, 69, 4)]
assert len(boss_levels) == 17
boss_total = sum(2500 + 100 * ((l // 4) % 17) for l in boss_levels)
print(f"boss: {len(boss_levels)}, totale {boss_total}")

# --- tesori/calice/sciami ---
treasures = 6 * 51 * 150
chalices = 51 * 300
bats = 76 * 40
print(f"tesori {treasures}, calici {chalices}, sciami {bats}")

# --- range min/max ---
enemies_min = kills * avg_orig
enemies_max = kills * avg_all
tot_min = enemies_min + mb_total + boss_total + treasures + chalices + bats
tot_max = enemies_max + mb_total + boss_total + treasures + chalices + bats
print(f"TOTALE min ~{tot_min/1000:.0f}k  max ~{tot_max/1000:.0f}k")
comp = {
    "nemici": (enemies_min + enemies_max) / 2,
    "mini-boss": mb_total,
    "boss": boss_total,
    "tesori": treasures,
    "calici+sciami": chalices + bats,
}
tot_c = sum(comp.values())
for k, v in comp.items():
    print(f"  {k}: {v/1000:.1f}k ({v/tot_c*100:.0f}%)")

# --- curva XP proposta: cumulata 1000 x n^1.75, arrotondata a 50 ---
import math
def xp_cum(n):
    return int(round(1000 * (n ** 1.75) / 50.0) * 50)
levels = []
for n in range(1, 26):
    levels.append({
        "livello": n,
        "xp_cumulata": xp_cum(n),
        "xp_per_livello": xp_cum(n) - xp_cum(n - 1) if n > 1 else 0,
    })
# livello raggiungibile col max
max_reach = max(n for n in range(1, 40) if xp_cum(n) <= tot_max)
min_reach = max(n for n in range(1, 40) if xp_cum(n) <= tot_min)
print(f"livello raggiungibile: min {min_reach}, max {max_reach}")

# soglie interessanti
for n in [2, 5, 10, 15, 20, max_reach]:
    print(f"  L{n}: {xp_cum(n):,} XP")

# --- vita extra: ogni 50k ---
extra_lives = int(tot_max // 50000)
print(f"vite extra da soglia (max): {extra_lives}")

out = {
    "enemy_vals": {"min": min(all_vals), "max": max(all_vals),
                   "avg_orig": round(avg_orig, 1), "avg_all": round(avg_all, 1),
                   "per_type": vals},
    "kills": kills, "mb_total": mb_total, "mb_count": len(mb_types),
    "boss_total": boss_total, "boss_count": 17,
    "treasures": treasures, "chalices": chalices, "bats": bats,
    "tot_min": round(tot_min), "tot_max": round(tot_max),
    "composition": {k: round(v) for k, v in comp.items()},
    "levels": levels, "max_reach": max_reach, "min_reach": min_reach,
    "extra_lives": extra_lives,
}
with open("/home/z/my-project/scripts/task98_data.json", "w") as f:
    json.dump(out, f, indent=1, ensure_ascii=False)
print("salvato scripts/task98_data.json")

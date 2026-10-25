#!/usr/bin/env python3
"""Task 57 fix: i container FX Node2D (fireball+particelle) devono essere
ignorati da TUTTI i loop che iterano i nodi proiettili.

Root cause: il filtro storico era `proj is GPUParticles2D` (Task 39), ma il
nuovo container di spawn_explosion e' Node2D puro -> veniva avanzato come
proiettile, colpiva i pilastri OGNI FRAME (distruggeva i muri in rovina)
e poteva colpire il player come fantasma.

Fix: gruppo "fx_effect" sul container + filtro is_in_group in ogni loop
proiettili (BossRoomController 829/955/2520 + MainGameController
663/1455/1787). I loop di cleanup (queue_free di tutti i children) restano
invariati: eliminare anche gli FX e' corretto.
"""
import re

edits = [
    # --- EffectsManager: container nel gruppo fx_effect ---
    ("godot/scripts/core/EffectsManager.gd",
     "        var root := Node2D.new()\n        root.position = pos\n",
     "        var root := Node2D.new()\n        root.position = pos\n"
     "        # TASK 57: gruppo che identifica i container FX (fireball +\n"
     "        # particelle) nei loop dei nodi proiettili (lezione Task 39:\n"
     "        # gli effetti aggiunti ai nodi proiettili NON sono proiettili)\n"
     "        root.add_to_group(\"fx_effect\")\n"),
    # --- BossRoomController loop advance (829) ---
    ("godot/scripts/core/BossRoomController.gd",
     "                if proj is GPUParticles2D:\n                        continue\n",
     "                if proj is GPUParticles2D or proj.is_in_group(\"fx_effect\"):\n"
     "                        continue\n"),
    # --- BossRoomController loop collision player (955) ---
    ("godot/scripts/core/BossRoomController.gd",
     "        for proj in boss_projectiles_node.get_children():\n"
     "                if not proj is Node2D or not proj.visible:\n"
     "                        continue\n"
     "                if proj.position.distance_squared_to(p.get_pixel_pos()) < 600.0:\n",
     "        for proj in boss_projectiles_node.get_children():\n"
     "                if not proj is Node2D or not proj.visible:\n"
     "                        continue\n"
     "                if proj.is_in_group(\"fx_effect\"):\n"
     "                        continue\n"
     "                if proj.position.distance_squared_to(p.get_pixel_pos()) < 600.0:\n"),
    # --- BossRoomController loop draw (2520) ---
    ("godot/scripts/core/BossRoomController.gd",
     "        for proj in boss_projectiles_node.get_children():\n"
     "                if not proj is Node2D:\n"
     "                        continue\n"
     "                var ppos: Vector2 = proj.position\n",
     "        for proj in boss_projectiles_node.get_children():\n"
     "                if not proj is Node2D:\n"
     "                        continue\n"
     "                if proj.is_in_group(\"fx_effect\"):\n"
     "                        continue\n"
     "                var ppos: Vector2 = proj.position\n"),
]

for path, old, new in edits:
    src = open(path, encoding="utf-8").read()
    if src.count(old) != 1:
        raise SystemExit(f"PATTERN NON UNIVOCO ({src.count(old)}x) in {path}:\n{old[:80]}")
    src = src.replace(old, new)
    open(path, "w", encoding="utf-8").write(src)
    print(f"patched {path}")

# MainGameController: 3 loop proiettili con guardia Node2D -> aggiungi fx skip
src = open("godot/scripts/core/MainGameController.gd", encoding="utf-8").read()
old_guard = "                if not proj is Node2D:\n                        continue\n"
new_guard = ("                if not proj is Node2D:\n                        continue\n"
             "                if proj.is_in_group(\"fx_effect\"):\n"
             "                        continue\n")
n = src.count(old_guard)
# sostituisci solo le occorrenze NEI LOOP enemy_projectiles (le prime 2:
# 664 e 1456; la 1788 ha guardia diversa)
lines = src.split("\n")
out = []
i = 0
patched = 0
while i < len(lines):
    out.append(lines[i])
    if "for proj in enemy_projectiles_node.get_children():" in lines[i]:
        # trova la guardia Node2D nelle prossime 3 righe e aggiungi fx skip
        for j in range(i + 1, min(i + 4, len(lines))):
            if "if not proj is Node2D" in lines[j]:
                # aggiungi dopo il continue della guardia
                out.append(lines[j])  # if ...
                out.append(lines[j + 1])  # continue
                out.append('                if proj.is_in_group("fx_effect"):')
                out.append("                        continue")
                i = j + 1
                patched += 1
                break
    i += 1
open("godot/scripts/core/MainGameController.gd", "w", encoding="utf-8").write("\n".join(out))
print(f"MainGameController: {patched} loop patchati")

## shot_task81.gd — TASK 81/81c: screenshot FANTASMI LENZUOLO + CELLE ZOMBIE
## + GEMME (verifica -30%).
##
## Due livelli, due scatti ciascuno:
##   - livello 2  (palette 1 blue dungeon, 1 cella zombie, ondate da 2)
##   - livello 8  (palette 7 teal abyss, 3 celle zombie, ondate da 3)
## TASK 81c — cadenza a ondate (L2: [bianco,rosso] ogni 25s; L8: tutti e 3
## ogni 5s): per avere lenzuoli in volo allo scatto si forza l'ondata a
## t=2.0s (force_launch sui primi ghost_wave_size(level) fantasmi, bianco
## e rosso al L2, tutti e 3 al L8) insieme alle braccia delle celle
## (force_out). Scatto 1 a t=2.8s (lenzuoli a meta' corridoio emersi, braccia
## OUT); scatto 2 a t=8.0s (braccia ritratte, nessun lenzuolo: la prossima
## ondata naturale arriva oltre lo scatto).
##
## Il dump CAP81 include anche i TESORI (posizioni+tipi) per la verifica
## pixel della riduzione del 30% di GEM (zaffiro blu) e RUBY (rubino rosso)
## e le POSIZIONI dei lenzuoli in volo (crop per la verifica VLM).
##
## Avvio (Xvfb diretto, xauth non disponibile):
##   Xvfb :99 -screen 0 1920x1080x24 & DISPLAY=:99 <godot> --path . \
##     res://tests/shot_task81.tscn
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var shot: int = 0
var forced: bool = false

const LEVELS: Array = [2, 8]
const NAMES: Array = [
        "task81_l2_ghosts_arms.png",
        "task81_l2_later.png",
        "task81_l8_ghosts_arms.png",
        "task81_l8_later.png",
]


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.player1_character = C.CharacterType.ELF
        _boot_level(LEVELS[0])


func _boot_level(level: int) -> void:
        if main != null:
                main.queue_free()
        GameManager.current_level = level
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        t = 0.0
        shot = 0
        forced = false
        print("[SHOT] boot MainGame livello ", level)


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        # a t=2.0s: braccia fuori su tutte le celle zombie + ondata fantasmi
        # forzata (i primi ghost_wave_size(level) lenzuoli in volo subito:
        # bianco+rosso al L2, tutti e 3 al L8)
        if not forced and t > 2.0:
                forced = true
                for p in main.zombie_cells.cell_positions():
                        main.zombie_cells.force_out(p.x, p.y)
                var w: int = C.ghost_wave_size(GameManager.current_level)
                for i in range(w):
                        main.maze_ghosts.force_launch(i)
                print("[SHOT] braccia forzate su ", main.zombie_cells.cell_positions(),
                                " + ondata di ", w, " fantasmi")
        if t > 2.8 and shot == 0:
                _capture(NAMES[stage * 2])
                shot = 1
        elif t > 8.0 and shot == 1:
                _capture(NAMES[stage * 2 + 1])
                shot = 2
                stage += 1
                if stage >= LEVELS.size():
                        print("[SHOT] fantasmi attivi L8: ",
                                        main.maze_ghosts.active_count())
                        get_tree().quit(0)
                        return
                _boot_level(LEVELS[stage])


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname, " (fantasmi attivi: ",
                        main.maze_ghosts.active_count(), ")")
        # TASK 81 debug: verifica pixel del volto zombie per ogni cella
        for p in main.zombie_cells.cell_positions():
                var green: int = 0
                for y in range(80 + p.y * 64, 80 + p.y * 64 + 64, 2):
                        for x in range(p.x * 64, p.x * 64 + 64, 2):
                                var col: Color = img.get_pixel(x, y)
                                if col.g > col.r + 0.1 and col.g > col.b + 0.1:
                                        green += 1
                print("[SHOT] cella ", p, " verdi=", green, " phase=",
                                main.zombie_cells.cell_phase(p.x, p.y),
                                " is_wall=", main.maze.is_wall(p.x, p.y))
        print("[SHOT] dynamic_walls: ", main.maze.dynamic_walls.keys())
        # TASK 81b: geometria esatta per la verifica pixel esterna
        # (cells+facciate+phase, wall_color del livello, 3 muri di
        # riferimento lontani dalle celle) — JSON su una riga CAP81.
        var cells_json: Array = []
        for p in main.zombie_cells.cell_positions():
                var d: Vector2i = main.zombie_cells.cell_facing(p.x, p.y)
                cells_json.append({"c": p.x, "r": p.y, "dir": [d.x, d.y],
                                "phase": main.zombie_cells.cell_phase(p.x, p.y)})
        var refs: Array = []
        var done: bool = false
        for r in range(2, C.MAZE_ROWS - 2):
                if done:
                        break
                for c in range(2, C.MAZE_COLS - 2):
                        if not main.maze.is_wall(c, r):
                                continue
                        if main.maze.dynamic_walls.has("%d,%d" % [c, r]):
                                continue
                        var far: bool = true
                        for p in main.zombie_cells.cell_positions():
                                if absi(c - p.x) + absi(r - p.y) < 4:
                                        far = false
                                        break
                        if far:
                                refs.append([c, r])
                                if refs.size() >= 3:
                                        done = true
                                        break
        # TASK 81c: tesori (posizioni+tipi, per la verifica -30% delle
        # gemme) e lenzuoli in volo (posizioni, per i crop VLM).
        var tres_json: Array = []
        for r in range(C.MAZE_ROWS):
                for c in range(C.MAZE_COLS):
                        if main.maze.get_cell_type(c, r) == C.CellType.TREASURE:
                                tres_json.append({"c": c, "r": r,
                                                "t": main.maze._get_cell_treasure(c, r)})
        var ghosts_json: Array = []
        for gi in range(main.maze_ghosts.ghost_count()):
                var gs: Dictionary = main.maze_ghosts.ghost_state(gi)
                if bool(gs.get("active", false)):
                        ghosts_json.append({"color": gs["color"],
                                        "pos": [gs["pos"].x, gs["pos"].y]})
        var wc: Color = main.maze.wall_color
        print("CAP81 ", JSON.stringify({
                "file": fname,
                "level": GameManager.current_level,
                "wall_color": [wc.r, wc.g, wc.b],
                "cells": cells_json,
                "ref_walls": refs,
                "treasures": tres_json,
                "ghosts": ghosts_json,
        }))

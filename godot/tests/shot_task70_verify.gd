## shot_task70_verify.gd — TASK 70: verifica IN-GIOCO dei fix
## "ancora il portale sta sotto il muro" + "rubino e gioiello blu ancora grandi".
##
## Istanzia la scena REALE MainGame.tscn e produce DUE screenshot:
##   A. task70_portal.png — portale attivo in cella EMPTY con muri N/E/S,
##      glow_pulse forzato a PI/4 (= pulse MASSIMO 1.06, caso peggiore:
##      se il vortice entra nella cella a pulse max, entra sempre)
##   B. task70_treasures.png — fila di 5 celle TREASURE (crown/gold/chest/
##      gem/ruby) come in shot_task68, per il confronto delle dimensioni
##
## Lancio:
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task70_verify.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var portal_cell: Vector2i = Vector2i.ZERO
var portal_pos: Vector2 = Vector2.ZERO
var treasure_cells: Array = []   # [{cell: Vector2i, type: int, name: String}]


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT70] boot MainGame 1P...")


func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                print("[SHOT70] TIMEOUT")
                get_tree().quit(1)
                return
        if main == null or not is_instance_valid(main) or not main.is_node_ready():
                return
        if stage == 0:
                _setup_all()
                stage = 1
                return
        # foto unica con portale attivo (pulse max) + tesori in fila
        if stage == 1 and t > 1.6:
                _snap("task70_portal_and_treasures.png")
                stage = 2
        elif stage == 2:
                get_tree().quit(0)


func _setup_all() -> void:
        main.start_level(3)
        var maze: Node = main.maze
        var C := GameConstants
        var ui_h: float = float(C.UI_HEIGHT)
        var tile: float = float(C.TILE_SIZE)

        # --- PORTALE: cella EMPTY con muri a N, E, S (il caso peggiore) ---
        var best: Vector2i = Vector2i(-1, -1)
        var best_d: int = 99999
        var mid_c: int = C.MAZE_COLS / 2
        var mid_r: int = C.MAZE_ROWS / 2
        for c in range(2, C.MAZE_COLS - 2):
                for r in range(2, C.MAZE_ROWS - 2):
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        if maze.get_cell_type(c + 1, r) != C.CellType.WALL:
                                continue
                        if maze.get_cell_type(c, r - 1) != C.CellType.WALL:
                                continue
                        if maze.get_cell_type(c, r + 1) != C.CellType.WALL:
                                continue
                        var d: int = abs(c - mid_c) + abs(r - mid_r)
                        if d < best_d:
                                best_d = d
                                best = Vector2i(c, r)
        if best.x >= 0:
                portal_cell = best
                var sp: Node = main.spawner
                sp.magic_portal.active = true
                sp.magic_portal.phase = 1
                sp.magic_portal.phase_timer = 40000
                sp.magic_portal.spawn_timer = 40000
                sp.magic_portal.enemies_to_spawn = 0
                sp.magic_portal.rotation = 0.0
                # PI/4 -> sin(pglow*2)=1 -> pulse MAXIMO 1.06 (caso peggiore)
                sp.magic_portal.glow_pulse = PI / 4.0
                sp.magic_portal.pos = Vector2(
                                float(best.x) * tile + tile / 2.0,
                                ui_h + float(best.y) * tile + tile / 2.0)
                portal_pos = sp.magic_portal.pos
                print("[SHOT70] portale (pulse max) in cella (", best.x, ",",
                                best.y, ") pos=", portal_pos,
                                " muri a N/E/S confermati")
        else:
                print("[SHOT70] NESSUNA cella con muri N/E/S: fallback solo E")
                for c in range(2, C.MAZE_COLS - 2):
                        for r in range(2, C.MAZE_ROWS - 2):
                                if maze.get_cell_type(c, r) == C.CellType.EMPTY \
                                                and maze.get_cell_type(c + 1, r) == C.CellType.WALL:
                                        portal_cell = Vector2i(c, r)
                                        var sp2: Node = main.spawner
                                        sp2.magic_portal.active = true
                                        sp2.magic_portal.phase = 1
                                        sp2.magic_portal.phase_timer = 40000
                                        sp2.magic_portal.spawn_timer = 40000
                                        sp2.magic_portal.enemies_to_spawn = 0
                                        sp2.magic_portal.rotation = 0.0
                                        sp2.magic_portal.glow_pulse = PI / 4.0
                                        sp2.magic_portal.pos = Vector2(
                                                        float(c) * tile + tile / 2.0,
                                                        ui_h + float(r) * tile + tile / 2.0)
                                        portal_pos = sp2.magic_portal.pos
                                        break
                        if portal_cell.x >= 0:
                                break
                print("[SHOT70] portale fallback in cella ", portal_cell)

        # --- TESORI: fila di 5 celle EMPTY (le stesse del task68) ---
        var names := ["crown", "gold", "chest", "gem", "ruby"]
        var ttypes := [C.TreasureType.CROWN, C.TreasureType.GOLD,
                        C.TreasureType.CHEST, C.TreasureType.GEM,
                        C.TreasureType.RUBY]
        var tr: int = -1
        var tc: int = -1
        var td: int = 99999
        for r in range(2, C.MAZE_ROWS - 2):
                for c in range(1, C.MAZE_COLS - 6):
                        var ok: bool = true
                        for k in 5:
                                if maze.get_cell_type(c + k, r) != C.CellType.EMPTY:
                                        ok = false
                                        break
                        if not ok:
                                continue
                        var d: int = abs(r - mid_r) + abs(c + 2 - mid_c)
                        if d < td:
                                td = d
                                tr = r
                                tc = c
        if tr >= 0:
                for k in 5:
                        var cellv: Vector2i = Vector2i(tc + k, tr)
                        maze._set_cell_type(cellv.x, cellv.y, C.CellType.TREASURE)
                        maze._set_cell_treasure(cellv.x, cellv.y, ttypes[k])
                        treasure_cells.append({
                                "cell": cellv, "type": ttypes[k], "name": names[k]})
                print("[SHOT70] tesori in fila: celle (", tc, ",", tr, ")..(",
                                tc + 4, ",", tr, ")")
                for e in treasure_cells:
                        print("[SHOT70]   tesoro ", e["name"], " @cella ",
                                        e["cell"])
        else:
                print("[SHOT70] NESSUNA fila di 5 celle EMPTY trovata")
                get_tree().quit(1)


func _snap(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT70] salvato ", fname)

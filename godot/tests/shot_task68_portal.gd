## shot_task68_portal.gd — TASK 68: riproduzione IN-GIOCO del bug utente
## "il portale viene disegnato 'sotto' il muro (rett. rosso)".
##
## Istanzia la scena REALE MainGame.tscn, avvia un livello, attiva il
## portale magico in una cella EMPTY con muro immediatamente ADIACENTE
## (scelta deterministica: la prima cella vuota con muro a est), aspetta
## l'animazione e cattura:
##   A. screenshot fullscreen
##   B. dati del portale (pos, cella, muro adiacente) stampati a log per
##      l'analisi pixel deterministica del crop (script Python separato)
##
## Lancio (pattern task 65/67):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task68_portal.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var captured: int = 0
var portal_screen_pos: Vector2 = Vector2.ZERO
var portal_cell: Vector2i = Vector2i.ZERO
var wall_side: String = ""


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT68] boot MainGame 1P...")


func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                print("[SHOT68] TIMEOUT")
                get_tree().quit(1)
                return
        if main == null or not main.is_node_ready():
                return
        if captured == 0:
                _setup_portal()
                captured = 1
                return
        # aspetta 1.6s di animazione (vortice in movimento) poi scatta
        if captured == 1 and t > 1.6:
                _snap("task68_portal_full.png")
                captured = 2
        elif captured == 2:
                get_tree().quit(0)


func _setup_portal() -> void:
        main.start_level(3)
        var maze: Node = main.maze
        var C := GameConstants
        var ui_h: float = float(C.UI_HEIGHT)
        var tile: float = float(C.TILE_SIZE)
        # cerca la cella EMPTY piu' vicina al centro con un muro a EST
        # (cosi' il lato destro del portale 84px sborda 10px sul muro)
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
                        # anche sud per avere un angolo di muro visibile
                        var d: int = abs(c - mid_c) + abs(r - mid_r)
                        if d < best_d:
                                best_d = d
                                best = Vector2i(c, r)
        if best.x < 0:
                print("[SHOT68] nessuna cella con muro a est trovata")
                get_tree().quit(1)
                return
        portal_cell = best
        var sp: Node = main.spawner
        sp.magic_portal.active = true
        sp.magic_portal.phase = 1  # spawning: visibile e stabile
        sp.magic_portal.phase_timer = 40000  # non chiudere
        sp.magic_portal.spawn_timer = 40000
        sp.magic_portal.enemies_to_spawn = 0  # niente spawn: solo visual
        sp.magic_portal.rotation = 0.0
        sp.magic_portal.glow_pulse = 0.0
        sp.magic_portal.pos = Vector2(
                        float(best.x) * tile + tile / 2.0,
                        ui_h + float(best.y) * tile + tile / 2.0)
        portal_screen_pos = sp.magic_portal.pos
        wall_side = "EST"
        print("[SHOT68] portale attivo in cella (", best.x, ",", best.y,
                        ") pos=", sp.magic_portal.pos,
                        " muro adiacente a ", wall_side)
        print("[SHOT68] TILE=", tile, " UI_HEIGHT=", ui_h)


func _snap(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT68] salvato ", fname, " portale@", portal_screen_pos)

## shot_task68_treasures.gd — TASK 68: verifica IN-GAME dell'uniformita'
## delle dimensioni dei 5 tesori (segnalazione utente: "i tesori del
## rettangolo celeste devono avere la stessa dimensione di quello del
## rettangolo verde").
##
## Istanzia la scena REALE MainGame.tscn, trova una fila di 5 celle EMPTY
## consecutive e le trasforma in celle TREASURE (una per tipo: crown, gold,
## chest, gem, ruby) usando le API reali del Maze, poi cattura uno
## screenshot del maze renderizzato come in gioco.
##
## Lancio (pattern task 65/67/68):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task68_treasures.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var captured: int = 0
var row_cells: Array = []


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT68T] boot MainGame 1P...")


func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                print("[SHOT68T] TIMEOUT")
                get_tree().quit(1)
                return
        if main == null or not main.is_node_ready():
                return
        if captured == 0:
                _setup_treasures()
                captured = 1
                return
        if captured == 1 and t > 1.2:
                _snap("task68_treasures_after.png")
                captured = 2
        elif captured == 2:
                get_tree().quit(0)


func _setup_treasures() -> void:
        main.start_level(3)
        var maze: Node = main.maze
        var C := GameConstants
        # cerca la riga con 5 celle EMPTY consecutive piu' vicina al centro
        var best_row: int = -1
        var best_col: int = -1
        var best_d: int = 99999
        var mid_r: int = C.MAZE_ROWS / 2
        for r in range(2, C.MAZE_ROWS - 2):
                var run: int = 0
                for c in range(2, C.MAZE_COLS - 2):
                        if maze.get_cell_type(c, r) == C.CellType.EMPTY:
                                run += 1
                                if run >= 5:
                                        var c0: int = c - 4
                                        var d: int = abs(r - mid_r) \
                                                        + abs(c0 + 2 - C.MAZE_COLS / 2)
                                        if d < best_d:
                                                best_d = d
                                                best_row = r
                                                best_col = c0
                        else:
                                run = 0
        if best_row < 0:
                print("[SHOT68T] nessuna fila di 5 celle EMPTY trovata")
                get_tree().quit(1)
                return
        var types: Array = [C.TreasureType.CROWN, C.TreasureType.GOLD,
                        C.TreasureType.CHEST, C.TreasureType.GEM,
                        C.TreasureType.RUBY]
        for i in range(5):
                var c: int = best_col + i
                maze._set_cell_type(c, best_row, C.CellType.TREASURE)
                maze._set_cell_treasure(c, best_row, int(types[i]))
                row_cells.append(Vector2i(c, best_row))
                print("[SHOT68T] cella (", c, ",", best_row, ") tesoro tipo ",
                                types[i])
        print("[SHOT68T] fila impostata: riga ", best_row,
                        " colonne ", best_col, "..", best_col + 4)


func _snap(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT68T] salvato ", fname, " celle=", row_cells)

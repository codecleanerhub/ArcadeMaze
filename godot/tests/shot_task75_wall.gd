## shot_task75_wall.gd — TASK 75: verifica muri = pattern screen (texture
## roccia Task 57 RIPRISTINATA) SENZA angoli (bevel per-cellula rimossi).
##
## Test visivo deterministico nel maze REALE (pattern shot_task72):
##   1) Massa di muri 3x3 + pareti: la superficie deve mostrare i MASSI
##      ORGANICI della vecchia texture (irregolari, contorni scuri) e
##      NESSUNA griglia di giunzioni/outline per-cellula, NESSUN bevel
##      NW/SE (richiesta utente: "quel pattern senza gli angoli").
##   2) Confronto affiancato col riferimento: l'utente ha fornito lo
##      screen del pattern voluto (upload pasted_image_1793038566604.png).
##
## Avvio (Xvfb, NON headless): scripts/xvfb_shot.sh 1920x1080 \
##   res://tests/shot_task75_wall.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

const MASS_C0: int = 10
const MASS_R0: int = 4


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


func _process(delta: float) -> void:
        t += delta
        if main == null or not is_node_ready():
                return
        if stage == 0 and t > 1.2:
                _setup()
                stage = 1
        elif stage == 1 and t > 2.2:
                _capture("task75_walls_pattern.png")
                stage = 2
        elif stage == 2:
                get_tree().quit(0)


func _setup() -> void:
        var maze = main.maze
        # pulisce i muri mobili nell'area di test (una lastra aperta si
        # disegna come pavimento e falserebbe il pattern)
        for c in range(MASS_C0 - 2, MASS_C0 + 5):
                for r in range(MASS_R0 - 2, MASS_R0 + 5):
                        maze.dynamic_walls.erase("%d,%d" % [c, r])
        # massa 3x3 di muri circondata da celle EMPTY su tutti i lati
        for c in range(MASS_C0 - 1, MASS_C0 + 4):
                for r in range(MASS_R0 - 1, MASS_R0 + 4):
                        var is_mass: bool = (c >= MASS_C0 and c <= MASS_C0 + 2) \
                                        and (r >= MASS_R0 and r <= MASS_R0 + 2)
                        maze._set_cell_type(c, r,
                                        maze.C.CellType.WALL if is_mass
                                        else maze.C.CellType.EMPTY)
        maze.queue_redraw()
        print("[SHOT] maze di test pronto (massa muri 3x3)")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

## shot_task72_walls_portal.gd — TASK 72: verifica muri uniformi + portale
## sopra i muri (z-index).
##
## Test visivo deterministico nel maze REALE:
##   1) Massa di muri 3x3 (celle 10..12, 4..6): col nuovo render i bevel 3D
##      appaiono SOLO sui bordi esposti verso i corridoi, niente giunzioni
##      interne; la texture e' la nuova PixelLab uniforme (nessuna "sfumatura
##      angolare" random).
##   2) Portale magico in cella circondata da muri su N/E/S: il vortice
##      deve essere INTERAMENTE visibile (disegnato DOPO i muri).
##
## Cattura la schermata e salva due PNG (vista piena + crop zoom).
##
## Avvio (Xvfb, NON headless):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1920x1080 \
##     res://tests/shot_task72_walls_portal.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0


# celle della massa di muro di test
const MASS_C0: int = 10
const MASS_R0: int = 4
# cella del portale di test (aperta a ovest, muri su N/E/S)
const PORTAL_C: int = 10
const PORTAL_R: int = 8


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


var stage: int = 0


func _process(delta: float) -> void:
        t += delta
        if main == null or not is_node_ready():
                return
        # pattern a due stadi (lezione shot_task70): setup PRESTO, cattura
        # ~1s dopo — il maze si e' ridisegnato su MOLTI frame col layout di
        # test (catturare nello stesso tick del queue_redraw becca il frame
        # vecchio: primo giro del harness aveva il portale assente)
        if stage == 0 and t > 1.2:
                _setup()
                stage = 1
        elif stage == 1 and t > 2.2:
                # pulse massimo = caso peggiore per il vortice
                main.spawner.magic_portal.glow_pulse = PI / 4.0
                _capture("task72_walls_portal.png")
                stage = 2
        elif stage == 2:
                get_tree().quit(0)


func _setup() -> void:
        var maze = main.maze
        # pulisce i muri di roccia MOBILI (Task 30) nell'area di test: una
        # lastra aperta si disegna come pavimento e falserebbe i bevel
        for c in range(MASS_C0 - 2, MASS_C0 + 5):
                for r in range(MASS_R0 - 2, PORTAL_R + 3):
                        maze.dynamic_walls.erase("%d,%d" % [c, r])
        # 1) massa 3x3 di muri (celle 10..12, 4..6): bordi esposti verso le
        #    celle EMPTY attorno su TUTTI i lati
        for c in range(MASS_C0 - 1, MASS_C0 + 4):
                for r in range(MASS_R0 - 1, MASS_R0 + 4):
                        var is_mass: bool = (c >= MASS_C0 and c <= MASS_C0 + 2) \
                                        and (r >= MASS_R0 and r <= MASS_R0 + 2)
                        maze._set_cell_type(c, r,
                                        maze.C.CellType.WALL if is_mass
                                        else maze.C.CellType.EMPTY)
        # 2) cella portale: aperta a OVEST, muri su NORD/EST/SUD
        for d in [[0, -1], [1, 0], [0, 1]]:
                maze._set_cell_type(PORTAL_C + d[0], PORTAL_R + d[1],
                                maze.C.CellType.WALL)
        maze._set_cell_type(PORTAL_C, PORTAL_R, maze.C.CellType.EMPTY)
        maze._set_cell_type(PORTAL_C - 1, PORTAL_R, maze.C.CellType.EMPTY)
        # attiva il portale esattamente nella cella di test
        main.spawner.magic_portal.pos = Vector2(
                        PORTAL_C * 64 + 32.0, PORTAL_R * 64 + 80 + 32.0)
        main.spawner.magic_portal.active = true
        main.spawner.magic_portal.rotation = 0.0
        main.spawner.magic_portal.glow_pulse = 0.0
        main.spawner.magic_portal.phase = 3  # chiuso: niente spawn nemici
        maze.queue_redraw()
        print("[SHOT] maze di test pronto (massa muri + portale)")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

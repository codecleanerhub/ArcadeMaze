## shot_task81.gd — TASK 81: screenshot FANTASMI LENZUOLO + CELLE ZOMBIE.
##
## Due livelli, due scatti ciascuno:
##   - livello 2  (palette 1 blue dungeon, 1 cella zombie)
##   - livello 8  (palette 7 teal abyss, 3 celle zombie)
## Scatto 1 (~6s): braccia FORZATE estese su tutte le celle (force_out a
## t=5s) + eventuali fantasmi in attraversamento (spawn 1.5-4s + RNG seedato
## per livello = riproducibile).
## Scatto 2 (~12s): fantasmi (altri o stessa traversata avanzata), braccia
## ormai ritratte (negli scatti si valuta anche il riposo della cella).
##
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task81.tscn 90
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
        # a t=5s forza le braccia fuori su tutte le celle zombie
        if not forced and t > 5.0:
                forced = true
                for p in main.zombie_cells.cell_positions():
                        main.zombie_cells.force_out(p.x, p.y)
                print("[SHOT] braccia forzate su ", main.zombie_cells.cell_positions())
        if t > 6.0 and shot == 0:
                _capture(NAMES[stage * 2])
                shot = 1
        elif t > 12.0 and shot == 1:
                _capture(NAMES[stage * 2 + 1])
                shot = 2
                stage += 1
                if stage >= LEVELS.size():
                        print("[SHOT] fantasmi attivi L8: ",
                                        main.maze_ghosts.active_count() if stage == 2 else "-")
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

## shot_task79d_maze.gd — TASK 79d: screenshot del pavimento del labirinto
## con le nuove palette GRIGIO ROCCIA (3 livelli = 3 palette diverse):
##   1. livello 1  -> palette 0 grey cavern (grigio roccia caldo)
##   2. livello 6  -> palette 1 blue dungeon (grigio-azzurro)
##   3. livello 14 -> palette 2 purple crypt (grigio-viola)
## Verifica VLM: pavimento chiaro "grigio roccia", muri leggibili, contrasto
## sufficiente per personaggi scuri (elf).
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task79d_maze.tscn 90
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

const LEVELS: Array = [2, 3]
const NAMES: Array = [
        "task79d_maze_floor_p1.png",
        "task79d_maze_floor_p2.png",
]


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        _boot_level(LEVELS[0])


func _boot_level(level: int) -> void:
        if main != null:
                main.queue_free()
        GameManager.current_level = level
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        t = 0.0
        print("[SHOT] boot MainGame livello ", level)


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        if t > 2.5:
                _capture(NAMES[stage])
                stage += 1
                if stage >= LEVELS.size():
                        get_tree().quit(0)
                        return
                _boot_level(LEVELS[stage])


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

## shot_task80_maze.gd — TASK 80: screenshot del labirinto DUNGEON SCURO con
## le LUCI LANTERNE (rollback muri TASK 78 + rollback pavimento TASK 79d):
##   1. livello 1  -> palette 0 grey cavern (elf, torce, lanterna eroe)
##   2. livello 2  -> palette 1 blue dungeon
##   3. livello 6  -> palette 5 green swamp
## Personaggio = ELF (il caso segnalato: player scuro difficile da vedere).
## Verifica VLM: muri rocciosi scuri (dungeon), pavimento scuro con POZZE DI
## LUCE CALDA attorno alle torce e al personaggio, elf leggibile per contrasto.
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task80_maze.tscn 90
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

const LEVELS: Array = [1, 2, 6]
const NAMES: Array = [
        "task80_maze_lanterns_p0.png",
        "task80_maze_lanterns_p1.png",
        "task80_maze_lanterns_p5.png",
]


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        # Caso utente: personaggio ELF (scuro) difficile da vedere sul buio.
        GameManager.player1_character = C.CharacterType.ELF
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

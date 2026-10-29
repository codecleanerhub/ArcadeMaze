## shot_task88_blades.gd — TASK 88: screenshot delle lame-ruota nel
## labirinto (livello 58 = 5 lame). PNG sequence via --write-movie.
## Avvio: bash scripts/xvfb_shot.sh res://tests/shot_task88_blades.tscn \
##            /home/z/my-project/download/task88_blades 30 45
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const C = preload("res://scripts/core/GameConstants.gd")


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 58
        GameManager.game_mode = C.GameMode.STORY
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame livello 58 (5 lame-ruota)")

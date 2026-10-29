## shot_task87_collapse.gd — TASK 87: screenshot dell'animazione di morte del
## player (collasso a terra + gemito). PNG sequence via --write-movie.
## Avvio: bash scripts/xvfb_shot.sh res://tests/shot_task87_collapse.tscn \
##            /home/z/my-project/download/task87_collapse 30 55
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var t: float = 0.0
var stage: int = 0
var main: Node2D = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.current_level = 1
        GameManager.game_mode = C.GameMode.STORY
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame livello 1")


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready() or main.player == null:
                return
        match stage:
                0:
                        # player al centro-scena, morte immediata al frame 8
                        main.player.position = Vector2(960.0, 520.0)
                        main.player.spawn_guard_ms = 0.0
                        main.player.damage_timer = 0
                        if t > 0.27:
                                main.player.energy = 1
                                main.player.take_damage()
                                stage = 1
                                t = 0.0
                                print("[SHOT] morte forzata al centro — collasso in corso")
                1:
                        # il collasso dura ~1.2s, il respawn arriva dopo:
                        # continua a catturare fino al quit-after del wrapper
                        pass

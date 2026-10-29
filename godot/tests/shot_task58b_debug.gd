## shot_task58b_debug.gd — TASK 58b debug: apre la card DENTRO MainGame
## (come il gioco vero), stampa lo stato delle texture demo e cattura.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[DBG] boot MainGame")


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.2:
                                main._maybe_show_bonus_card(
                                                CollectiblesClass.Kind.HAMMER, 1)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.35:
                                var card = main._bonus_card
                                if card == null:
                                        print("[DBG] FAIL: card NULL")
                                else:
                                        print("[DBG] card class script = ",
                                                        card.get_script().resource_path)
                                        print("[DBG] flag = ",
                                                        card.DEMO_REAL_SPRITES_ENABLED)
                                        print("[DBG] char_type = ",
                                                        card.demo_char_type)
                                        print("[DBG] player_tex = ",
                                                        card._demo_player_tex)
                                        print("[DBG] enemy_tex = ",
                                                        card._demo_enemy_tex)
                                        print("[DBG] ally_tex = ",
                                                        card._demo_ally_tex)
                                _capture("task58b_debug.png")
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[DBG] salvato ", fname)

## shot_task51_bonuscard.gd — TASK 51: screenshot della CARD BONUS.
## Catture della card del martello (card completa + demo animata a meta'
## ciclo) e della card del bastone del fulmine, per verifica visiva.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var shot_count: int = 0


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


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
                        # demo a meta' ciclo (martello in volo verso il muro)
                        if t > 1.35:
                                _capture("task51_card_hammer.png")
                                # chiudi e apri quella del bastone del fulmine
                                if main._bonus_card != null:
                                        main._bonus_card.queue_free()
                                        main._bonus_card = null
                                        get_tree().paused = false
                                main._maybe_show_bonus_card(
                                                CollectiblesClass.Kind.SCEPTER, 1)
                                stage = 2
                                t = 0.0
                2:
                        if t > 1.9:
                                _capture("task51_card_scepter.png")
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

## shot_task58b_bonuscard.gd — TASK 58b: screenshot delle CARD BONUS con
## sprite REALI nella demo (player PixelLab del raccoglitore, mostro reale).
## Catture: martello (volo), congelamento (blocco ghiaccio), scettro
## (fulmini su sprite tinte), per verifica visiva degli stati.
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
                        # martello in volo verso il muro (demo animata)
                        if t > 1.35:
                                _capture("task58b_card_hammer.png")
                                _swap(CollectiblesClass.Kind.FREEZE_SCROLL)
                2:
                        # raggio congelante appena passato + nemico ghiacciato
                        if t > 2.0:
                                _capture("task58b_card_freeze.png")
                                _swap(CollectiblesClass.Kind.SCEPTER)
                3:
                        # fulmini che folgorano le sprite tinte di giallo
                        if t > 1.9:
                                _capture("task58b_card_scepter.png")
                                get_tree().quit(0)


func _swap(kind: int) -> void:
        if main._bonus_card != null:
                main._bonus_card.queue_free()
                main._bonus_card = null
                get_tree().paused = false
        main._maybe_show_bonus_card(kind, 1)
        stage += 1
        t = 0.0


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

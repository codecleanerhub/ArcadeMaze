## shot_task65_cards.gd — TASK 65e: screenshot delle BONUS CARD con gli
## item REALI PixelLab al posto delle figure procedurali (feedback utente:
## "nelle card delle armi ci sono elementi procedurali nel video").
## Cattura 7 card (hammer, dynamite, boots, potion, mine, chalice, freeze)
## al momento del loop in cui l'item PNG e' piu' visibile.
##
## Avvio (Xvfb, NON headless):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1280x720 \
##     res://tests/shot_task65_cards.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

# kind -> (file, tempo di cattura nel loop demo 4.6s)
const CARDS := [
        [CollectiblesClass.Kind.HAMMER, "task65_card_hammer.png", 1.25],
        [CollectiblesClass.Kind.DYNAMITE, "task65_card_dynamite.png", 0.55],
        [CollectiblesClass.Kind.SPEED_BOOTS, "task65_card_boots.png", 0.7],
        [CollectiblesClass.Kind.POTION, "task65_card_potion.png", 0.55],
        [CollectiblesClass.Kind.MINE, "task65_card_mine.png", 1.0],
        [CollectiblesClass.Kind.CHALICE, "task65_card_chalice.png", 0.6],
        [CollectiblesClass.Kind.FREEZE_SCROLL, "task65_card_freeze.png", 1.2],
]


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


func _process(delta: float) -> void:
        t += delta
        if stage == 0:
                if main != null and main.is_node_ready() and t > 1.2:
                        _show_card(0)
                        stage = 1
        else:
                var entry: Array = CARDS[stage - 1]
                if t > float(entry[2]):
                        _capture(str(entry[1]))
                        if stage >= CARDS.size():
                                get_tree().quit(0)
                        else:
                                _show_card(stage)
                                stage += 1


func _show_card(idx: int) -> void:
        if main._bonus_card != null:
                main._bonus_card.queue_free()
                main._bonus_card = null
                get_tree().paused = false
        GameManager.reset_run()
        var entry: Array = CARDS[idx]
        main._maybe_show_bonus_card(int(entry[0]), 1, "unicorn")
        t = 0.0
        print("[SHOT] card ", idx, " (kind ", entry[0], ")")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

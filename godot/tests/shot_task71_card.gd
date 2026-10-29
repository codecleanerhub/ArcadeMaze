## shot_task71_card.gd — TASK 71: verifica della CARD della statuetta dopo il
## fix "due sprite". Cattura la card unicorn a 3 istanti della timeline demo:
##   t=0.50  statua che brilla (ancora nessun alleato)
##   t=1.05  BURST di evocazione (statua che dissolve, alleato che appare)
##   t=2.35  carica — deve essere visibile SOLO l'alleato animato, NESSUNA
##           statuetta residua (feedback utente: "si deve vedere soltanto
##           quello che si muove")
## e la card knight a t=2.35 (stessa verifica sulla seconda variante).
##
## Avvio (Xvfb, NON headless):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1280x720 \
##     res://tests/shot_task71_card.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

# [variante, tempo cattura, nome file]
const SHOTS := [
        ["unicorn", 0.50, "task71_card_unicorn_statua.png"],
        ["unicorn", 1.05, "task71_card_unicorn_burst.png"],
        ["unicorn", 2.35, "task71_card_unicorn_carica.png"],
        ["knight", 2.35, "task71_card_knight_carica.png"],
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
                        _show(str(SHOTS[0][0]))
        else:
                var entry: Array = SHOTS[stage - 1]
                if t > float(entry[1]):
                        _capture(str(entry[2]))
                        if stage >= SHOTS.size():
                                get_tree().quit(0)
                        else:
                                _show(str(SHOTS[stage][0]))


func _show(variant: String) -> void:
        if main._bonus_card != null:
                main._bonus_card.queue_free()
                main._bonus_card = null
                get_tree().paused = false
        # la card si mostra solo alla PRIMA raccolta per run: reset per run
        GameManager.reset_run()
        main._maybe_show_bonus_card(CollectiblesClass.Kind.KNIGHT_STATUE, 1,
                        variant)
        stage += 1
        t = 0.0
        print("[SHOT] card ", variant, " (stage ", stage, ")")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

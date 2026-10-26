## shot_task75_card.gd — TASK 75: verifica card della statua UNICORNO
## (statua PETRIFICATA dal frame reale dell'alleato, pipeline Task 74).
##
## Catture (variant unicorn, livelli dispari):
##   1) card t=0.50 — STATUA nuova a 58px (arte pietrificata, prima 34px
##      arte vecchia grezza) che brilla
##   2) card t=2.35 — carica: SOLO l'alleato unicorno animato (regressione
##      Task 71: NESSUN doppio sprite, la statua e' dissolta)
##   3) pickup IN-GAME: statua a terra con aura accanto al player
##
## Avvio (Xvfb, NON headless): scripts/xvfb_shot.sh 1280x800 \
##   res://tests/shot_task75_card.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

const VARIANT := "unicorn"


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT] boot MainGame")


func _process(delta: float) -> void:
        t += delta
        if main == null or not is_node_ready():
                return
        if stage == 0 and t > 1.2:
                _show_card()
        elif stage == 1 and t > 0.50:
                _capture("task75_card_unicorn_statua.png")
                stage = 2
                t = 0.0
        elif stage == 2 and t > 1.85:
                _capture("task75_card_unicorn_carica.png")
                stage = 3
                if main._bonus_card != null:
                        main._bonus_card.queue_free()
                        main._bonus_card = null
                        get_tree().paused = false
                _spawn_pickup()
                t = 0.0
        elif stage == 3 and t > 1.0:
                _capture("task75_pickup_unicorn_ingame.png")
                stage = 4
                get_tree().quit(0)


func _show_card() -> void:
        GameManager.reset_run()
        main._maybe_show_bonus_card(CollectiblesClass.Kind.KNIGHT_STATUE, 1,
                        VARIANT)
        stage = 1
        t = 0.0
        print("[SHOT] card unicorn (statua petrificata nuova)")


func _spawn_pickup() -> void:
        var st: Collectibles = CollectiblesClass.make_knight_statue(
                        Vector2(420.0, 260.0))
        st.statue_variant = VARIANT
        main.add_child(st)
        print("[SHOT] pickup statua unicorn a terra")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

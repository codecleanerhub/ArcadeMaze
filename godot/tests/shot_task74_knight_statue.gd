## shot_task74_knight_statue.gd — TASK 74: verifica statua del cavaliere
## RIFATTA (petrificazione del frame reale dell'alleato).
##
## Catture:
##   1) card knight t=0.50 — la STATUA nuova (arte PixelLab pietrificata,
##      ~51x57 massiccia come l'alleato) che brilla: non piu' la vecchia
##      statua "grezza" 30px
##   2) card knight t=2.35 — carica: SOLO l'alleato animato (regressione
##      Task 71: nessuna statuetta residua)
##   3) pickup IN-GAME: statua a terra con aura (Collectibles, variante
##      knight) accanto al player per confronto di scala
##
## Avvio (Xvfb, NON headless):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1280x720 \
##     res://tests/shot_task74_knight_statue.tscn
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0

const VARIANT := "knight"


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
                _capture("task74_card_knight_statua.png")
                stage = 2
                t = 0.0
        elif stage == 2 and t > 1.85:
                # t card totale = 0.50 attesi + 1.85 = 2.35 dalla nascita
                _capture("task74_card_knight_carica.png")
                stage = 3
                # chiude la card e passa al pickup in-game
                if main._bonus_card != null:
                        main._bonus_card.queue_free()
                        main._bonus_card = null
                        get_tree().paused = false
                _spawn_pickup()
                t = 0.0
        elif stage == 3 and t > 1.0:
                _capture("task74_pickup_ingame.png")
                stage = 4
                get_tree().quit(0)


func _show_card() -> void:
        GameManager.reset_run()
        main._maybe_show_bonus_card(CollectiblesClass.Kind.KNIGHT_STATUE, 1,
                        VARIANT)
        stage = 1
        t = 0.0
        print("[SHOT] card knight (statua nuova)")


func _spawn_pickup() -> void:
        # statua a terra variante knight accanto alla cella del player
        var st: Collectibles = CollectiblesClass.make_knight_statue(
                        Vector2(420.0, 260.0))
        st.statue_variant = VARIANT
        main.add_child(st)
        print("[SHOT] pickup statua knight a terra")


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

## shot_task64_card.gd — TASK 64: screenshot delle BONUS CARD della
## statuetta nelle due varianti per livello. Prima (livelli dispari) la card
## mostra titolo "Statua dell'Unicorno", icona statuetta unicorno e demo con
## lo sheet unicorn_ally; poi (livelli pari) "Statua del Cavaliere", icona
## statuetta cavaliere e demo con lo sheet knight_ally.
##
## Avvio (Xvfb, NON headless):
##   Xvfb :99 & DISPLAY=:99 <godot> --path . --resolution 1280x720 \
##     res://tests/shot_task64_card.tscn
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
                                # livello 1 (dispari): variante unicorn
                                main._maybe_show_bonus_card(
                                                CollectiblesClass.Kind.KNIGHT_STATUE, 1, "unicorn")
                                stage = 1
                                t = 0.0
                1:
                        # demo avanzata: alleato emerso e in carica verso il nemico
                        if t > 2.35:
                                _capture("task64_card_unicorn.png")
                                _swap("knight")
                2:
                        # livello pari: variante knight
                        if t > 2.35:
                                _capture("task64_card_knight.png")
                                get_tree().quit(0)


func _swap(variant: String) -> void:
        if main._bonus_card != null:
                main._bonus_card.queue_free()
                main._bonus_card = null
                get_tree().paused = false
        # la card si mostra solo alla PRIMA raccolta per run: reset per
        # poter riaprire la statuetta con l'altra variante
        GameManager.reset_run()
        main._maybe_show_bonus_card(CollectiblesClass.Kind.KNIGHT_STATUE, 1, variant)
        stage += 1
        t = 0.0


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

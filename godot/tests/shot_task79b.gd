## shot_task79b.gd — TASK 79b: verifica TRADUZIONI in ITALIANO.
##
## Cattura (xvfb, NON headless), con I18n.set_language(ITALIAN):
##   1. MainMenu IT — voci GIOCATORI/MODALITÀ/TEST MODE/IMPOSTAZIONI/
##      INIZIA PARTITA/CREDITS/HALL OF FAME
##   2. MainMenu sottomenu OPTIONS IT — header PNG oro "IMPOSTAZIONI" +
##      voci MUSICA/LINGUA/CONFIGURA JOYSTICK/INDIETRO
##   3. SelectPlayer IT — "SELEZIONA GIOCATORE 1" + nome "EROE" in basso
##   4. ContinuesOverlay IT — "GIOCATORE 2", SÌ/NO, CONTINUE RIMASTI, hint
##
## A fine test la lingua torna ENGLISH (default del gioco, richiesta Task 44)
## per non lasciare il config.ini di test sporco.
##
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task79b.tscn
extends Node

var t: float = 0.0
var stage: int = 0
var current: Node = null
var overlay: CanvasLayer = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        I18n.set_language(I18n.Language.ITALIAN)
        current = load("res://scenes/MainMenu.tscn").instantiate()
        get_tree().root.add_child.call_deferred(current)
        print("[SHOT] boot MainMenu (ITALIANO)")


func _process(delta: float) -> void:
        t += delta
        if not is_node_ready():
                return
        match stage:
                0:
                        if t > 2.5 and current != null and current.is_node_ready():
                                _capture("task79b_menu_it.png")
                                current._set_in_options(true)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.0:
                                _capture("task79b_options_it.png")
                                _swap("res://scenes/SelectPlayer.tscn")
                                stage = 2
                                t = 0.0
                2:
                        if t > 1.2:
                                _capture("task79b_select_it.png")
                                # ContinuesOverlay (2P): overlay puro, .new()+setup
                                current.queue_free()
                                current = null
                                overlay = load("res://scripts/ui/ContinuesOverlay.gd").new()
                                overlay.setup(2, 3)
                                get_tree().root.add_child.call_deferred(overlay)
                                stage = 3
                                t = 0.0
                3:
                        if t > 1.5:
                                _capture("task79b_continue_it.png")
                                _finish()


func _swap(scene_path: String) -> void:
        if current != null:
                current.queue_free()
        current = load(scene_path).instantiate()
        get_tree().root.add_child.call_deferred(current)
        t = 0.0
        print("[SHOT] scena -> ", scene_path)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)


func _finish() -> void:
        # Lingua di test -> ENGLISH (default) per lasciare il config pulito.
        I18n.set_language(I18n.Language.ENGLISH)
        get_tree().quit(0)

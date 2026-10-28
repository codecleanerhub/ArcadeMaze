## shot_task79c.gd — TASK 79b: regressione ENGLISH del logo OPTIONS.
## Dopo lo switch per-lingua, verifica che il sottomenu in EN mostri ancora
## l'header PNG "OPTIONS" (gold) e le voci inglesi.
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task79c.tscn
extends Node

var t: float = 0.0
var stage: int = 0
var current: Node = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        I18n.set_language(I18n.Language.ENGLISH)
        current = load("res://scenes/MainMenu.tscn").instantiate()
        get_tree().root.add_child.call_deferred(current)
        print("[SHOT] boot MainMenu (ENGLISH)")


func _process(delta: float) -> void:
        t += delta
        if not is_node_ready():
                return
        match stage:
                0:
                        if t > 2.5 and current != null and current.is_node_ready():
                                _capture("task79c_options_en.png")
                                current._set_in_options(true)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.0:
                                _capture("task79c_options_en.png")
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

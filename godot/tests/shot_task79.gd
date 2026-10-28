## shot_task79.gd — TASK 79: screenshot delle schermate col font medievale
## "Arcadia Gothic" (originale, palette ORO/osso/pietra — niente sangue).
##
## Cattura (xvfb, NON headless):
##   1. MainMenu (logo oro Arcadia Gothic + voci osso/oro + hint pietra)
##   2. MainMenu sottomenu OPTIONS (header oro)
##   3. HallOfFame (header oro + tabella osso, top3 oro)
##   4. SelectPlayer (titolo gold_48 + nome oro)
##   5. Credits (sezioni oro, ruoli pietra, nomi osso)
##   6. ConfigJoy (title gold_48 + step/hint gotici)
##
## Avvio: scripts/xvfb_shot.sh 1920x1080 res://tests/shot_task79.tscn
extends Node

var t: float = 0.0
var stage: int = 0
var current: Node = null


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        current = load("res://scenes/MainMenu.tscn").instantiate()
        get_tree().root.add_child.call_deferred(current)
        print("[SHOT] boot MainMenu")


func _process(delta: float) -> void:
        t += delta
        if not is_node_ready():
                return
        match stage:
                0:
                        if t > 2.5 and current != null and current.is_node_ready():
                                _capture("task79_menu_gold.png")
                                current._set_in_options(true)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.0:
                                _capture("task79_options_gold.png")
                                _swap("res://scenes/HallOfFame.tscn")
                                stage = 2
                                t = 0.0
                2:
                        if t > 1.2:
                                _capture("task79_hof_gold.png")
                                _swap("res://scenes/SelectPlayer.tscn")
                                stage = 3
                                t = 0.0
                3:
                        if t > 1.2:
                                _capture("task79_select_gold.png")
                                _swap("res://scenes/CreditsScreen.tscn")
                                stage = 4
                                t = 0.0
                4:
                        if t > 22.0:
                                _capture("task79_credits_gold.png")
                                _swap("res://scenes/ConfigJoy.tscn")
                                stage = 5
                                t = 0.0
                5:
                        if t > 1.5:
                                _capture("task79_configjoy_gold.png")
                                get_tree().quit(0)


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

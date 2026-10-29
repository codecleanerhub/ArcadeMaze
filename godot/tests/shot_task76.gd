## shot_task76.gd — TASK 76: screenshot delle schermate modificate.
##
## Cattura (xvfb, NON headless):
##   1. MainMenu con logo "ARCADE MAZE FANTASY" (niente gocce)
##   2. MainMenu sottomenu OPTIONS (logo sangue + roulette RIMOSSA dal bg)
##   3. HallOfFame (header sangue + palette rossa)
##   4. SelectPlayer (ruota con anello di pietra PixelLab)
##   5. Credits (sfondo con UN solo braccio pollice-su)
##   6. WinScreen 1P (personaggio usato: VAMPIRE)
##   7. WinScreen 2P (KNIGHT + DRAGON)
##   8. DemoMode 2 frame (nuova AI BFS)
##
## Avvio: scripts/xvfb_shot.sh 1280x720 res://tests/shot_task76.tscn
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
                                _capture("task76_menu_main.png")
                                current._set_in_options(true)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.0:
                                _capture("task76_menu_options.png")
                                _swap("res://scenes/HallOfFame.tscn")
                                stage = 2
                                t = 0.0
                2:
                        if t > 1.2:
                                _capture("task76_halloffame.png")
                                _swap("res://scenes/SelectPlayer.tscn")
                                stage = 3
                                t = 0.0
                3:
                        if t > 1.2:
                                _capture("task76_select_player.png")
                                _swap("res://scenes/CreditsScreen.tscn")
                                stage = 4
                                t = 0.0
                4:
                        if t > 5.0:
                                _capture("task76_credits.png")
                                _win(1)
                                stage = 5
                                t = 0.0
                5:
                        if t > 1.5:
                                _capture("task76_win_1p.png")
                                _win(2)
                                stage = 6
                                t = 0.0
                6:
                        if t > 1.5:
                                _capture("task76_win_2p.png")
                                _swap("res://scenes/DemoMode.tscn")
                                stage = 7
                                t = 0.0
                7:
                        if t > 4.0:
                                _capture("task76_demo_1.png")
                                stage = 8
                                t = 0.0
                8:
                        if t > 5.0:
                                _capture("task76_demo_2.png")
                                get_tree().quit(0)


func _swap(scene_path: String) -> void:
        if current != null:
                current.queue_free()
        current = load(scene_path).instantiate()
        get_tree().root.add_child.call_deferred(current)
        t = 0.0
        print("[SHOT] scena -> ", scene_path)


func _win(players: int) -> void:
        if current != null:
                current.queue_free()
        GameManager.reset_run()
        GameManager.num_players = players
        GameManager.player1_character = 8  # VAMPIRE
        GameManager.player2_character = 5  # KNIGHT
        GameManager.final_level = 68
        GameManager.final_score = 123450 if players == 1 else 210000
        GameManager.final_score_p1 = 123450
        GameManager.final_score_p2 = 86550
        current = load("res://scenes/WinScreen.tscn").instantiate()
        get_tree().root.add_child.call_deferred(current)
        t = 0.0
        print("[SHOT] WinScreen %dP" % players)


func _capture(fname: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT] salvato ", fname)

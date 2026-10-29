## shot_bonus33.gd — TASK 33: screenshot della schermata bonus con il NUOVO
## ordinamento di potenza crescente. Incontri 1 (liv 4: le piu' scarse) e
## 6 (liv 24: le piu' forti) a confronto.
extends Node2D

var t := 0.0
var main: Node2D = null
var bonus: CanvasLayer = null
var stage := 0

func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)

func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if t > 1.2 and bonus == null and main != null and main.is_node_ready():
                                bonus = load("res://scripts/ui/BonusScreen.gd").new()
                                bonus.setup(4, [main.player])
                                add_child(bonus)
                                stage = 1
                                t = 0.0
                1:
                        if t > 1.5:
                                _capture("bonus_encounter1_weakest.png")
                                bonus.queue_free()
                                bonus = load("res://scripts/ui/BonusScreen.gd").new()
                                bonus.setup(24, [main.player])
                                add_child(bonus)
                                stage = 2
                                t = 0.0
                2:
                        if t > 1.5:
                                _capture("bonus_encounter6_strongest.png")
                                get_tree().quit(0)

func _capture(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        img.save_png("/home/z/my-project/download/" + fname)
        print("[SHOT33] salvato ", fname)

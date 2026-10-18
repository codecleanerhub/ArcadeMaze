## shot_bonus.gd — TASK 23: cattura screenshot REALE della schermata bonus
## con icone PNG + sfondo fucina (xvfb + --write-movie, pattern shot_wheel).
extends Node2D

var t := 0.0
var main: Node2D = null
var bonus: CanvasLayer = null


func _ready() -> void:
        GameManager.num_players = 2
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if t > 1.2 and bonus == null and main != null and main.is_node_ready():
                bonus = load("res://scripts/ui/BonusScreen.gd").new()
                bonus.setup(4, [main.player, main.player2])
                add_child(bonus)

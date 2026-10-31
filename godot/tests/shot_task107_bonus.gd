## shot_task107_bonus.gd — TASK 23/107: screenshot REALE della schermata
## bonus (xvfb + --write-movie, pattern shot_bonus). TASK 108: la riga
## riscatto cuori e' stata RIMOSSA (il cuore si compra nello SHOP del mago):
## la card mostra SOLO le tre reliquie.
extends Node2D

var t := 0.0
var main: Node2D = null
var bonus: CanvasLayer = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 2
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if t > 1.2 and bonus == null and main != null and main.is_node_ready():
                main.player.score = 30000
                main.player.lives = 2
                main.player2.score = 9100
                main.player2.lives = 3
                bonus = load("res://scripts/ui/BonusScreen.gd").new()
                bonus.setup(4, [main.player, main.player2])
                add_child(bonus)

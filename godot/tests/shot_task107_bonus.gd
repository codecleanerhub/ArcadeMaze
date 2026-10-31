## shot_task107_bonus.gd — TASK 107: screenshot REALE della schermata bonus
## con la riga RISCATTA CUORE sotto i riquadri delle reliquie (xvfb +
## --write-movie, pattern shot_bonus). P1 con punteggio realistico: riga
## attiva, focus sulla riga, 1 cuore scelto e preview dello score live.
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
                # punteggio da meta' run (dopo il boss 7): 3 cuori riscattabili
                main.player.score = 30000
                main.player.lives = 2
                main.player.hearts_redeemed = 0
                main.player2.score = 9100
                main.player2.lives = 3
                bonus = load("res://scripts/ui/BonusScreen.gd").new()
                bonus.setup(4, [main.player, main.player2])
                add_child(bonus)
        elif bonus != null and t > 1.6 and not bonus._redeem_focus:
                # focus sulla riga riscatto con 1 cuore scelto di 3:
                # contatore < 1 > + score 30000 -> 26000 + costo prossimo
                bonus._redeem_focus = true
                bonus._redeem_count = 1

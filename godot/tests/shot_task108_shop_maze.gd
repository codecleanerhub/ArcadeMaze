## shot_task108_shop_maze.gd — TASK 108: screenshot della CASA STREGA nel
## labirinto (xvfb + --write-movie). Player con punteggio da shop: la
## capanna sorge all'angolo (aperta); a metà ripresa il player entra,
## compra ed esce -> cartello CHIUSO.
extends Node2D

var t := 0.0
var main: Node2D = null
var phase := 0


func _ready() -> void:
        # Lo SHOP mette in pausa il tree: l'harness resta ALWAYS per guidare
        # ingresso/acquisto/uscita anche a pausa attiva (lezione Task 106).
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if phase == 0 and main != null and main.is_node_ready():
                main.player.score = 30000
                main.start_level(3)
                phase = 1
        elif phase == 1 and main.shop_stall != null:
                # porta il player davanti alla porta dello shop
                var stall = main.shop_stall
                main.player.position = stall.position + Vector2(0.0, 56.0)
                main.player.last_dx = 0
                main.player.last_dy = -1
                phase = 2
        elif phase == 2 and t > 2.2 and main._shop_screen == null:
                # entra nello shop (la schermata apre e mette in pausa)
                main.player.position = main.shop_stall.position
                main._update_shop_entry()
                if main._shop_screen != null:
                        phase = 3
        elif phase == 3 and t > 3.0:
                # compra un cuore ed ESCI -> cartello CHIUSO sulla porta
                var screen = main._shop_screen
                screen._buy_item(screen._item_defs()[1])
                screen._exit_shop()
                phase = 4

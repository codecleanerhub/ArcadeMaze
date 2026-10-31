## shot_task108_shop_ui.gd — TASK 108: screenshot dell'INTERNO del negozio
## del mago (mago PixelLab + box items: icona / descrizione / costo /
## ACQUISTA, ESCI). Punteggio 5200: cuore e medikit acquistabili, la BAMBOLA
## (6000) mostra il tasto ACQUISTA DISATTIVATO con "PUNTI INSUFFICIENTI".
extends Node2D

var t := 0.0
var main: Node2D = null
var screen: CanvasLayer = null


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if screen == null and main != null and main.is_node_ready():
                main.player.score = 5200
                main.player.lives = 2
                main.player.energy = 3
                main.player.voodoo_equipped = false
                screen = load("res://scripts/ui/ShopScreen.gd").new()
                screen.setup(main.player)
                add_child(screen)
                screen._sel = 0   # seleziona la bambola (l'item piu' costoso)

## shot_task108_voodoo.gd — TASK 108: screenshot della POSSESSIONE
## VOODOO in azione: il player guida il corpo del nemico (puppet figlio
## del player: sprite nemico al posto del personaggio) dopo che la sua
## anima (SoulTransferEffect) e' volata dentro.
extends Node2D

var t := 0.0
var main: Node2D = null
var phase := 0


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if phase == 0 and main != null and main.is_node_ready():
                main.start_level(3)
                phase = 1
        elif phase == 1 and not main.spawner.enemies.is_empty():
                # possiede il primo nemico: il corpo del player diventa il
                # nemico (puppet) con l'anima in volo sopra.
                var p: CharacterBody2D = main.player
                var enemy = main.spawner.enemies[0]
                # nemico vicino al player per una scena leggibile
                p.position = enemy.position + Vector2(-60.0, 0.0)
                main._apply_voodoo_possession(p, enemy)
                p.update_possession_puppet(16.0)
                phase = 2

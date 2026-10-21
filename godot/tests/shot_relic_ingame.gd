## shot_relic_ingame.gd — TASK 23: screenshot REALE del player con l'arma
## reliquia PNG IN MANO e del FENDENTE ANIMATO (arco della spada).
## xvfb + --write-movie: frame ad alto fps durante lo swing (250ms).
extends Node2D

var t := 0.0
var main: Node2D = null
var fired := false


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        if t > 1.5 and not fired:
                var p: CharacterBody2D = main.player
                # Spadone del Cavaliere equipaggiato (PNG in mano).
                p.current_weapon = GameConstants.make_relic_weapon(
                                GameConstants.RELIC_MELEE[0])
                p.armor_relic = GameConstants.RELIC_ARMORS[4].duplicate()  # fuoco
                p.armor_relic["charges"] = 20
                p.armor_relic["max_charges"] = 20
                p.last_dx = 1
                p.last_dy = 0
                # cella corridoio visibile al centro-ish.
                var cell := _find_corridor()
                p.set_position_abs(cell.x * 64.0 + 32.0, 80.0 + cell.y * 64.0 + 32.0)
                p.stamina = 1.0
                p.shoot_cooldown = 0
                p.shoot()  # -> _fire_relic -> melee_pending + fx swing
                fired = true


func _find_corridor() -> Vector2i:
        for r in range(4, 12):
                for c in range(8, 22):
                        if not main.maze.is_wall(c, r):
                                return Vector2i(c, r)
        return Vector2i(10, 6)

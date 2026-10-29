## shot_spawn_blink.gd — harness movie-mode per verificare se il lampeggio
## di nascita del player e' VISIBILE nel rendering reale (pipeline
## --write-movie gia' validata dai task 84-91). Boota MainGame 1P, tiene
## pulita l'area del player, NON esce da solo (ci pensa --quit-after):
## i frame PNG salvati mostrano se la luminanza della zona player oscilla
## col periodo del blink (~300ms) o resta piatta.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var last_report: float = 0.0
var _meta_written: bool = false


func _ready() -> void:
	GameManager.num_players = 1
	GameManager.reset_run()
	main = MainGameScene.instantiate()
	get_tree().root.add_child.call_deferred(main)
	print("[SHOT] boot MainGame 1P per blink movie...")


func _write_meta(p: CharacterBody2D) -> void:
	if _meta_written:
		return
	_meta_written = true
	var f := FileAccess.open("/tmp/spawn_blink_meta.txt", FileAccess.WRITE)
	if f != null:
		f.store_line(
			(
				"%d %d"
				% [
					int(p.get_global_transform_with_canvas().origin.x),
					int(p.get_global_transform_with_canvas().origin.y)
				]
			)
		)
		f.close()
	print("[SHOT] meta player pos scritta")


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or not main.is_node_ready():
		return
	for e in main.spawner.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	main.spawner.enemies.clear()
	for proj in main.enemy_projectiles_node.get_children():
		proj.queue_free()
	if t - last_report >= 0.5:
		last_report = t
		var p: CharacterBody2D = main.player
		if p != null:
			_write_meta(p)
			print(
				(
					"[SHOT] t=%.2f guard=%d modulate.a=%.2f pos=%s"
					% [
						t,
						p.spawn_guard_ms,
						p.modulate.a,
						p.get_global_transform_with_canvas().origin
					]
				)
			)

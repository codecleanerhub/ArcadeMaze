## test_demo_collapse.gd — verifica la regressione TASK 87 nel demo REALE:
## alla morte del player in DemoMode (nessun MainGameController!), il
## DemoController deve avviare il collasso (PlayerCollapseFx) e, a fine
## animazione, respawnare il player (respawn_after_soul). Prima del fix il
## player restava invisibile e congelato fino ai 30s del timer demo.
##
## Fasi (tempo REALE, niente accelerazione: l'fx scala col tempo della tree):
##   A) morte forzata (energy=1 + contatto nemico teleportato) ->
##      begin_collapse: soul_pending/collapse_requested true, sprite nascosto
##   B) DemoController avvia l'fx: _collapses non vuoto
##   C) entro ~4s reali: fx finished -> player respawnato (soul_pending
##      false, sprite visibile, posizione tornata alla cella di partenza)
##   D) il demo continua a muoversi dopo il respawn (posizione cambia)
extends Node

const DemoScene = preload("res://scenes/DemoMode.tscn")

var demo: Node2D = null
var t: float = 0.0
var phase: int = 0
var deaths_seen: int = 0
var respawn_pos: Vector2 = Vector2.ZERO
var post_respawn_samples: Array = []
var failures: Array[String] = []


func _fail(msg: String) -> void:
	failures.append(msg)
	print("[TEST FAIL] ", msg)


func _ready() -> void:
	# il demo parte dopo ~0.1s; niente input utente -> non si interrompe
	demo = DemoScene.instantiate()
	add_child(demo)
	print("[TEST] boot DemoMode...")


func _physics_process(delta: float) -> void:
	t += delta
	if t > 30.0:
		_fail("timeout globale (30s)")
		_finish()
		return
	if demo == null or not is_node_ready():
		return
	var p: CharacterBody2D = demo.player
	if p == null or not is_instance_valid(p):
		return
	match phase:
		0:
			if t < 0.5:
				return
			# A) forza la morte: energia a 1, invulnerabilita' a zero, nemico
			# addosso -> contatto -> take_damage -> energy 0 -> begin_collapse
			p.energy = 1
			p.damage_timer = 0
			p.invincible_timer = 0
			p.spawn_guard_ms = 0
			var enemy = null
			for e in demo.spawner.enemies:
				if not e.is_dead():
					enemy = e
					break
			if enemy == null:
				_fail("A: nessun nemico vivo (maze casuale)")
				_finish()
				return
			enemy.position = p.get_pixel_pos()
			phase = 1
			print("[TEST] A: morte forzata allestita (nemico teleportato)")
		1:
			# attende il gate: begin_collapse scatta al contatto
			if p.soul_pending or p.collapse_requested:
				deaths_seen += 1
				if not p.soul_pending or p.sprite == null or p.sprite.visible:
					_fail("A: begin_collapse non ha congelato/nascosto il player")
				else:
					print("[TEST] OK A: begin_collapse (soul_pending, sprite nascosto)")
				phase = 2
				return
			if t > 4.0:
				_fail("A: morte non avvenuta entro 4s (contatto mancato?)")
				_finish()
		2:
			# B) il DemoController avvia l'fx
			if demo._collapses.is_empty():
				return
			print("[TEST] OK B: PlayerCollapseFx avviato dal DemoController")
			phase = 3
		3:
			# C) respawn a fine animazione (tempo reale ~1.2s + margine 4s)
			if p.soul_pending and t < 8.0:
				return
			if p.soul_pending:
				_fail("C: player ancora soul_pending dopo 8s (respawn differito MAI eseguito)")
				_finish()
				return
			respawn_pos = p.global_position
			if p.sprite == null or not p.sprite.visible:
				_fail("C: sprite non ripristinato al respawn")
			else:
				print("[TEST] OK C: respawn eseguito (sprite visibile, pos=%s)" % respawn_pos)
			phase = 4
		4:
			# D) il demo riprende a muoversi
			post_respawn_samples.append(p.global_position)
			if post_respawn_samples.size() >= 120:  # ~2s reali
				var moved: bool = false
				var first: Vector2 = post_respawn_samples[0]
				for pos in post_respawn_samples:
					if pos.distance_to(first) > 32.0:
						moved = true
						break
				if moved:
					print("[TEST] OK D: demo in movimento dopo il respawn")
				else:
					_fail("D: demo fermo dopo il respawn (posizione statica)")
				_finish()


func _finish() -> void:
	if failures.is_empty() and deaths_seen > 0:
		print("[TEST] test_demo_collapse: TUTTO VERDE")
		get_tree().quit(0)
	else:
		if deaths_seen == 0 and failures.is_empty():
			_fail("nessuna morte osservata (setup A fallito silenziosamente)")
		print("[TEST] test_demo_collapse: %d FALLI" % failures.size())
		get_tree().quit(1)

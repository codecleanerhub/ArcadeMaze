## shot_task99_levelup.gd — TASK 99: screenshot della sequenza Level Up
## (annuncio fulmine + scritta, e la modale delle abilità con assegnazioni).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LoadingScreen.skip_boot_hold()
	GameManager.reset_run()
	main = MainGameScene.instantiate()
	get_tree().root.add_child.call_deferred(main)
	print("[SHOT] boot MainGame")


func _process(delta: float) -> void:
	t += delta
	match stage:
		0:
			if main != null and main.is_node_ready() and t > 1.2:
				# soglia L2: 3.350 punti -> level up con 1 punto
				main.player.add_score(3350)
				print("[SHOT] punti assegnati: level ",
						main.player.level,
						" pending ", main.player.pending_levelup_fx)
				stage = 1
				t = 0.0
		1:
			# annuncio in corso: fulmine + scritta LEVEL UP!
			if t > 0.85:
				_capture("task99_announce.png")
				stage = 2
				t = 0.0
		2:
			# fine annuncio -> modale aperta (1 punto da spendere)
			if t > 1.6 and main._levelup_card != null:
				_capture("task99_modal.png")
				# assegna Resistenza con la riga selezionata
				main._levelup_card._row = 1
				main._levelup_card._try_alloc(1)
				stage = 3
				t = 0.0
		3:
			if t > 0.35:
				_capture("task99_modal_alloc.png")
				get_tree().quit(0)


func _capture(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("/home/z/my-project/download/" + fname)
	print("[SHOT] salvato ", fname)

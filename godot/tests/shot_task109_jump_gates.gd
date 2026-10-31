## shot_task109_jump_gates.gd — TASK 109: screenshot della modale abilità
## con la progressione dei Salti Aggiuntivi COMPLETA (Resistenza 40 + salto 2):
## la riga del Salto Aggiuntivo mostra il 3° slot VISIBILE ma DISATTIVATO
## (badge "NON SBLOCCABILE" — richiesta utente: "si vedrà disattivata
## l'opzione"). Cattura anche lo stato bloccato del 2° salto (badge
## "RICHIEDE RESISTENZA 40") in un secondo stage.
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
				# Stage 1: 2° salto NON ancora comprato (Resistenza 40
				# raggiunta): badge "RICHIEDE RESISTENZA 40" sul 2° salto.
				main.player.confirm_skills({"stamina": 40, "jump": 1})
				main.player.skill_points = 3
				main._maybe_open_levelup_modal(1)
				stage = 1
				t = 0.0
		1:
			if t > 0.5 and main._levelup_card != null:
				_capture("task109_jump_req40.png")
				main._levelup_card._confirm()
				stage = 2
				t = 0.0
		2:
			# Stage 2: ENTRAMBI i salti comprati (Resistenza 40 + salto 2):
			# il 3° slot appare DISATTIVATO ("NON SBLOCCABILE").
			if t > 0.4:
				main.player.confirm_skills({"stamina": 40, "jump": 2})
				main.player.skill_points = 2
				main._maybe_open_levelup_modal(1)
				stage = 3
				t = 0.0
		3:
			if t > 0.5 and main._levelup_card != null:
				_capture("task109_jump_never.png")
				get_tree().quit(0)


func _capture(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("/home/z/my-project/download/" + fname)
	print("[SHOT] salvato ", fname)

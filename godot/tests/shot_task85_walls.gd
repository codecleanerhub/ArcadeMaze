## shot_task85_walls.gd — TASK 85: screenshot del labirinto livello 1 per
## analizzare i blocchi muro. Richiesta utente: alcuni blocchi muro mostrano
## una porzione piu' scura "a sfumatura d'angolo" (finestre della texture
## roccia che tagliano le zone di giunzione scura tra i massi). Tutti i
## blocchi devono avere l'aspetto uniforme dei blocchi OK (segni blu).
## Boot livello 1 (palette 0 grey cavern, come lo screen utente) + shot.
## Avvio: scripts/xvfb_shot.sh res://tests/shot_task85_walls.tscn 10 30
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var captured: bool = false


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        GameManager.num_players = 1
        GameManager.current_level = 1
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[SHOT85] boot MainGame livello 1")


func _process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        if t > 2.5 and not captured:
                captured = true
                var img := get_viewport().get_texture().get_image()
                img.save_png("/home/z/my-project/download/task85_walls_after.png")
                print("[SHOT85] salvato task85_walls_after.png ", img.get_size())
                get_tree().quit(0)

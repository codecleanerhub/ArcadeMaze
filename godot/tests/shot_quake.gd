## shot_quake.gd — TASK 31: screenshot dedicati del TERREMOTO:
## 1) marker crepe pulsanti sulle celle bersaglio durante il telegrafo;
## 2) masso a meta' caduta;
## 3) macerie dopo l'impatto.
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")
const H = preload("res://scripts/entities/MazeHazards.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _process(delta: float) -> void:
        t += delta
        match stage:
                0:
                        if main != null and main.is_node_ready() and t > 1.0:
                                main.start_level(12)
                                main.is_paused = true
                                var hz = main.hazards
                                hz.quake_timer_ms = 1.0
                                stage = 1
                                t = 0.0
                1:
                        # telegrafo avviato -> marker pronti
                        if t > 0.3:
                                main.hazards.update_hazards(16.0, main.maze)
                                for _i in 12:
                                        main.hazards.update_hazards(150.0, main.maze)
                                print("[SHOTQ] stato=", main.hazards.quake_state,
                                                " massi=", main.hazards.boulder_list.size())
                                _capture("quake_markers.png")
                                stage = 2
                                t = 0.0
                2:
                        # un masso a meta' caduta
                        if t > 0.3:
                                var hz = main.hazards
                                for b in hz.boulder_list:
                                        b["delay_ms"] = 0.0
                                        b["timer_ms"] = 130.0  # meta' caduta
                                        b["state"] = 1
                                        if b["sprite"] != null:
                                                b["sprite"].queue_free()
                                                b["sprite"] = null
                                        b["fall_sprite"] = hz._make_sprite(
                                                "res://assets/sprites/hazards/boulder.png",
                                                b["cell"], 58.0)
                                        b["fall_from"] = Vector2(
                                                        b["cell"].x * 64 + 32,
                                                        b["cell"].y * 64 + 32 + 80 - 420.0)
                                        b["fall_sprite"].position = b["fall_from"]
                                hz.update_hazards(1.0, main.maze)
                                _capture("quake_falling.png")
                                stage = 3
                                t = 0.0
                3:
                        # dopo l'impatto: macerie
                        if t > 0.3:
                                for _i in 60:
                                        main.hazards.update_hazards(16.0, main.maze)
                                _capture("quake_rubble.png")
                                var states: Array = []
                                for b in main.hazards.boulder_list:
                                        states.append(b["state"])
                                print("[SHOTQ] stati massi dopo impatto: ", states)
                                get_tree().quit(0)


func _capture(fname: String) -> void:
        var img: Image = get_viewport().get_texture().get_image()
        var path: String = "/home/z/my-project/download/" + fname
        var err: int = img.save_png(path)
        print("[SHOTQ] salvato ", path, " err=", err)

## shot_hazards_wall.gd — TASK 30: screenshot dedicato dei MURI DI ROCCIA
## nelle tre fasi del ciclo (OPEN / WARN / CLOSED). Boot MainGame, livello 12,
## pausa, pilotaggio diretto del ciclo via update_hazards a step, cattura di
## una porzione centrata sul muro per ciascuna fase.
extends Node2D

const MainGameScene = preload("res://scenes/MainGame.tscn")
const H = preload("res://scripts/entities/MazeHazards.gd")

var main: Node2D = null
var t: float = 0.0
var stage: int = 0
var wall: Dictionary = {}


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
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
                                wall = main.hazards.find_first(H.HazardType.ROCK_WALL)
                                if wall.is_empty():
                                        print("[SHOTW] nessun muro trovato")
                                        get_tree().quit(1)
                                        return
                                print("[SHOTW] muro @ ", wall["cell"],
                                                " axis=", wall["axis"])
                                # porta il muro a inizio fase OPEN
                                wall["phase"] = H.WallPhase.OPEN
                                wall["phase_ms"] = 0.0
                                stage = 1
                                t = 0.0
                1:
                        # OPEN: prime due lastre ritratte (0.35s nel ciclo)
                        if t > 0.35:
                                _dump_wall("OPEN-shot")
                                _capture("hazards_wall_open.png")
                                # avanza fino a WARN (2.9s rimanenti)
                                for _i in 40:
                                        main.hazards.update_hazards(100.0, main.maze)
                                        if wall["phase"] == H.WallPhase.WARN:
                                                break
                                stage = 2
                                t = 0.0
                2:
                        # WARN: vibrazione pre-chiusura
                        if t > 0.25:
                                _dump_wall("WARN-shot")
                                _capture("hazards_wall_warn.png")
                                for _i in 40:
                                        main.hazards.update_hazards(100.0, main.maze)
                                        if wall["phase"] == H.WallPhase.CLOSED:
                                                break
                                stage = 3
                                t = 0.0
                3:
                        # CLOSED: lastre compenetrate al centro
                        if t > 0.3:
                                _dump_wall("CLOSED-shot")
                                _capture("hazards_wall_closed.png")
                                print("[SHOTW] completato: fase finale=",
                                                wall["phase"])
                                get_tree().quit(0)


func _dump_wall(tag: String) -> void:
        var a: Sprite2D = wall["slab_a"]
        var b: Sprite2D = wall["slab_b"]
        print("[SHOTW] ", tag, " phase=", wall["phase"], " off_a=", wall["off_a"],
                        " off_b=", wall["off_b"], " A=", a.position, " B=", b.position,
                        " scale=", a.scale, " center=", Vector2(
                                        wall["cell"].x * 64 + 32,
                                        wall["cell"].y * 64 + 32 + 80))


func _capture(fname: String) -> void:
        var cell: Vector2i = wall["cell"]
        var img: Image = get_viewport().get_texture().get_image()
        # crop 4x3 celle centrato sul muro + upscale x2
        var cx: int = cell.x * 64 + 32
        var cy: int = cell.y * 64 + 32 + 80
        var box: Rect2i = Rect2i(cx - 128, cy - 96, 256, 192)
        var crop: Image = img.get_region(box)
        crop.resize(512, 384, Image.INTERPOLATE_NEAREST)
        var path: String = "/home/z/my-project/download/" + fname
        var err: int = crop.save_png(path)
        print("[SHOTW] salvato ", path, " err=", err)

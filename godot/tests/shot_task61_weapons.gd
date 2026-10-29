## shot_task61_weapons.gd — TASK 61c: screenshot delle 4 armi elementali
## PixelLab nuove (throwing_sword, fire_staff, ice_lance, ice_arrow)
## IN MANO al player (mira a destra e in su: verifica grip) + pickup
## elementali a terra (unione pool CAVALIERE+MAGO nel labirinto).
##
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task61c_movie/f.png \
##     --fixed-fps 10 --quit-after 70 res://tests/shot_task61_weapons.tscn
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

# [tipo, mira_x, mira_y]
const SPECS: Array = [
        [C.RelicType.THROWING_SWORD, 1, 0],
        [C.RelicType.THROWING_SWORD, 0, -1],
        [C.RelicType.FIRE_STAFF, 1, 0],
        [C.RelicType.ICE_LANCE, 1, 0],
        [C.RelicType.ICE_ARROW, 1, 0],
        [C.RelicType.ICE_LANCE, 0, -1],
]

var main: Node2D = null
var t: float = 0.0
var stage: int = -1
var stage_frames: Dictionary = {}


func _ready() -> void:
        LoadingScreen.skip_boot_hold()
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        if main == null or not main.is_node_ready():
                return
        if stage < 0:
                _setup()
                stage = 0
                t = 0.0
                _begin(0)
                return
        t += delta
        if t >= 1.2:
                stage += 1
                t = 0.0
                if stage >= SPECS.size():
                        print("[T61W] FINE")
                        get_tree().quit(0)
                        return
                _begin(stage)


func _setup() -> void:
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        main.player.set_character(C.CharacterType.KNIGHT, 1)
        # pavimento: unione pool CAVALIERE + MAGO (spade/asce/bastoni/lance)
        main.maze.affinity_char_types = [C.CharacterType.KNIGHT,
                        C.CharacterType.MAGE]
        main.maze.generate(GameManager.current_level)
        var spot := _find_open_cell()
        main.player.set_position_abs(spot.x * 64.0 + 32.0,
                        80.0 + spot.y * 64.0 + 32.0)
        print("[T61W] setup: knight a ", spot)


func _begin(idx: int) -> void:
        var spec: Array = SPECS[idx]
        var wd: Dictionary = C.make_relic_weapon(C.get_relic_def(int(spec[0])))
        wd["ground"] = true
        main.player.collect_weapon(wd)
        main.player.last_dx = int(spec[1])
        main.player.last_dy = int(spec[2])
        main.player.queue_redraw()
        stage_frames[idx] = Engine.get_frames_drawn()
        print("[T61W] STAGE ", idx, " type=", int(spec[0]),
                        " aim=(", spec[1], ",", spec[2], ") frame ",
                        Engine.get_frames_drawn())


func _find_open_cell() -> Vector2i:
        for r in range(4, 14):
                for c in range(6, 24):
                        if _open(c, r) and _open(c + 1, r) and _open(c + 2, r) \
                                        and _open(c, r - 1) and _open(c, r - 2):
                                return Vector2i(c, r)
        return Vector2i(10, 6)


func _open(c: int, r: int) -> bool:
        return not main.maze.is_wall(c, r)

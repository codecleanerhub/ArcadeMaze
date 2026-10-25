## shot_task61_dragon.gd — TASK 61: screenshot del set del DRAGO in-game.
##
## Il player DRAGO spara palle di fuoco PixelLab (set Task 60b riusato):
##   stage 0: FIREBALL_RED in volo verso uno zombie + pickup fiamma a terra
##   stage 1: colpo di grazia ROSSO -> nemico che brucia (fireaura)
##   stage 2: colpo di grazia BLU -> nemico statua di ghiaccio
## Verifica: coerenza drago+palle di fuoco (niente fucile in mano!), la
## fiamma blu diversa dalla rossa, pickup elementali sul pavimento.
##
##   Xvfb :99 & DISPLAY=:99 godot --path . --resolution 1920x1080 \
##     --write-movie /home/z/my-project/scripts/task61_movie/f.png \
##     --fixed-fps 10 --quit-after 80 res://tests/shot_task61_dragon.tscn
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var t: float = 0.0
var stage: int = -1
var victim1: Node2D = null
var victim2: Node2D = null
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
        # le vittime restano FERME (stun continuo) per uno shot deterministico
        if victim1 != null and is_instance_valid(victim1):
                victim1.apply_stun(2000)
        if victim2 != null and is_instance_valid(victim2):
                victim2.apply_stun(2000)
        if stage < 0:
                _setup()
                stage = 0
                t = 0.0
                stage_frames[0] = Engine.get_frames_drawn()
                print("[T61SHOT] STAGE 0 frame ", Engine.get_frames_drawn())
                return
        t += delta
        if Engine.get_frames_drawn() % 10 == 0:
                print("[T61SHOT] dbg t=", t, " stage=", stage,
                                " proj=", main.player.projectiles.size())
        if stage == 0 and t >= 2.5:
                # spara la palla rossa verso la vittima 1
                _shoot_at(victim1, C.RelicType.FIREBALL_RED)
                stage = 1
                t = 0.0
                stage_frames[1] = Engine.get_frames_drawn()
                print("[T61SHOT] STAGE 1 (fireball rossa in volo) frame ",
                                Engine.get_frames_drawn())
        elif stage == 1 and t >= 1.6:
                # uccide con la rossa (colpo di grazia -> brucia)
                _kill_with(victim1, C.RelicType.FIREBALL_RED)
                stage = 2
                t = 0.0
                stage_frames[2] = Engine.get_frames_drawn()
                print("[T61SHOT] STAGE 2 (brucia) frame ", Engine.get_frames_drawn())
        elif stage == 2 and t >= 2.2:
                # statua di ghiaccio con la fiamma blu
                _kill_with(victim2, C.RelicType.FLAME_BLUE)
                stage = 3
                t = 0.0
                stage_frames[3] = Engine.get_frames_drawn()
                print("[T61SHOT] STAGE 3 (statua ghiaccio) frame ",
                                Engine.get_frames_drawn())
        elif stage == 3 and t >= 1.6:
                print("[T61SHOT] FINE")
                get_tree().quit(0)


func _setup() -> void:
        # ripulisci i nemici d'esempio spawnati dal labirinto PRIMA di creare
        # le vittime deterministiche (che restano nello spawner per il loop hit)
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        # drago protagonista
        main.player.set_character(C.CharacterType.DRAGON, 1)
        main.maze.affinity_char_types = [C.CharacterType.DRAGON]
        main.maze.generate(GameManager.current_level)
        # arma elementale in mano: palla di fuoco rossa
        var def: Dictionary = C.get_relic_def(C.RelicType.FIREBALL_RED)
        var wd: Dictionary = C.make_relic_weapon(def)
        wd["ground"] = true
        main.player.collect_weapon(wd)
        # posizione centrale del corridoio
        var spot := _find_open_cell()
        main.player.set_position_abs(spot.x * 64.0 + 32.0,
                        80.0 + spot.y * 64.0 + 32.0)
        main.player.last_dx = 1
        main.player.last_dy = 0
        # due vittime deterministiche davanti al drago
        var E = load("res://scripts/enemies/Enemy.gd")
        victim1 = E.new()
        victim1.init(0, spot.x + 3, spot.y)
        main.spawner.enemies.append(victim1)
        main.add_child(victim1)
        victim2 = E.new()
        victim2.init(0, spot.x + 3, spot.y + 2)
        main.spawner.enemies.append(victim2)
        main.add_child(victim2)
        print("[T61SHOT] setup: drago a ", spot, " vittime a ",
                        victim1.get_pixel_pos(), " ", victim2.get_pixel_pos())


func _shoot_at(target: Node2D, w_type: int) -> void:
        var from: Vector2 = main.player.get_pixel_pos()
        var to: Vector2 = target.get_pixel_pos()
        # NOTE: nell'update dei proiettili "dir" e' UNITARIO e lo spostamento
        # e' dir * speed_px (default 8): mai passare velocita' dentro dir.
        var dirv: Vector2 = (to - from).normalized()
        main.player.projectiles.append({
                "pos": from + dirv * 20.0, "dir": dirv,
                "speed_px": 5.0, "power": 2, "active": true, "type": w_type,
        })
        main.player.queue_redraw()


func _kill_with(target: Node2D, w_type: int) -> void:
        target.health = 1
        main.player.character_type = C.CharacterType.DRAGON
        main.player.projectiles.append({
                "pos": target.get_pixel_pos(), "dir": Vector2(1, 0),
                "power": 2, "active": true, "type": w_type,
        })
        main._check_player_projectiles_vs_enemies(main.player)


func _find_open_cell() -> Vector2i:
        for r in range(4, 14):
                for c in range(6, 24):
                        if _open(c, r) and _open(c + 3, r) and _open(c + 3, r + 2) \
                                        and _open(c + 1, r) and _open(c + 2, r):
                                return Vector2i(c, r)
        return Vector2i(10, 6)


func _open(c: int, r: int) -> bool:
        return not main.maze.is_wall(c, r)

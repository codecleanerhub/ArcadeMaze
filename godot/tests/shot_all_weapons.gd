## shot_all_weapons.gd — TASK 24: screenshot REALI di TUTTE le 12 armi
## reliquie (6 mischia + 6 distanza) per la verifica visiva richiesta
## dall'utente ("verifica tutte le armi che hai fatto"):
##   * in mano, mira a destra e mira in su (PNG orientato dal grip);
##   * fendente a meta' (~50%) verso destra e sinistra per le 6 mischia.
## Ogni stato dura ~0.42s: con --write-movie --fixed-fps 10 si catturano
## 4 frame per stato; il frame centrale e' quello usato per il contact sheet.
## Nemici ripuliti e hurry-up resettati ad ogni frame: il player sopravvive
## ai ~17s di sequenza.
extends Node2D

const STATE_TIME: float = 0.42

var main: Node2D = null
var states: Array = []
var phase: int = -1
var state_t: float = 0.0
var all_defs: Array = []


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        all_defs = GameConstants.RELIC_MELEE.duplicate()
        all_defs.append_array(GameConstants.RELIC_RANGED)
        # [weapon_index, aim_dx, aim_dy, swing]
        for i in range(all_defs.size()):
                states.append([i, 1, 0, false])
                states.append([i, 0, -1, false])
                if i < GameConstants.RELIC_MELEE.size():
                        states.append([i, 1, 0, true])
                        states.append([i, -1, 0, true])
        var scene := load("res://scenes/MainGame.tscn") as PackedScene
        main = scene.instantiate()
        add_child.call_deferred(main)


func _process(delta: float) -> void:
        if main == null or not main.is_node_ready():
                return
        # sicurezza: niente nemici, niente hurry up durante lo shot.
        for e in main.spawner.enemies.duplicate():
                if is_instance_valid(e):
                        e.queue_free()
        main.spawner.enemies.clear()
        main._since_last_treasure_ms = 0.0
        if phase < 0:
                _begin_state(0)
                return
        var p: CharacterBody2D = main.player
        var st: Array = states[phase]
        if st[3]:
                # congela il fendente a meta' corsa per il frame catturato.
                p.melee_fx_timer_ms = 120
                p.queue_redraw()
        state_t += delta
        if state_t >= STATE_TIME:
                state_t = 0.0
                if phase + 1 < states.size():
                        _begin_state(phase + 1)
                else:
                        get_tree().quit()


func _begin_state(idx: int) -> void:
        phase = idx
        print("SHOT24_STATE ", phase, " frame ", Engine.get_frames_drawn())
        var st: Array = states[idx]
        var p: CharacterBody2D = main.player
        var rdef: Dictionary = all_defs[st[0]]
        p.current_weapon = GameConstants.make_relic_weapon(rdef)
        p.last_dx = int(st[1])
        p.last_dy = int(st[2])
        p.melee_fx_timer_ms = 0
        p.melee_fx_def = {}
        p.melee_fx_dir = Vector2(float(st[1]), float(st[2]))
        if st[3]:
                p.melee_fx_def = rdef
                p.melee_fx_timer_ms = 120
        # posizione: cella corridoio con spazio libero a destra e sopra.
        var cell := _find_open_cell()
        p.set_position_abs(cell.x * 64.0 + 32.0, 80.0 + cell.y * 64.0 + 32.0)
        p.queue_redraw()
        var cam := get_viewport().get_camera_2d()
        print("SHOT24_POS player=", p.global_position,
                        " cam_center=", cam.get_screen_center_position() if cam else Vector2.INF,
                        " weapon=", rdef.get("id"), " aim=(", st[1], ",", st[2], ")")


func _find_open_cell() -> Vector2i:
        ## Cella con 2 celle libere a destra e 2 sopra (per arma in mano e
        ## fendente senza compenetrazione immediata coi muri).
        for r in range(4, 14):
                for c in range(6, 24):
                        if _open(c, r) and _open(c + 1, r) and _open(c + 2, r) \
                                        and _open(c, r - 1) and _open(c, r - 2):
                                return Vector2i(c, r)
        return Vector2i(10, 6)


func _open(c: int, r: int) -> bool:
        return not main.maze.is_wall(c, r)

## test_barrels_quake.gd — Test funzionale runtime (headless) dei BARILI
## ESPLOSIVI e del TERREMOTO (Task 31):
##   A. COSTANTI: barrel_count_for_level (grace 4, 2 base, +1/6 livelli, cap
##      6), quake_events_for_level (0 < liv 6, 1, 2 dal liv 20),
##      quake_boulder_count (4 + liv/6, cap 10), rollback flags.
##   B. GENERAZIONE: livello 12 -> 3 barili su celle EMPTY, lontani dallo
##      spawn, non su collectible.
##   C. ESPLOSIONE: proiettile sulla cella = boom; nemico nel raggio
##      UCCISO (+5000 al player); player lontano illeso; player nel raggio
##      -33% energia max.
##   D. CATENA: due barili a 1 cella di distanza -> il primo innesca il
##      secondo (FUSE -> boom).
##   E. TERREMOTO: timer -> TELEGRAPH -> DROPPING con N massi; impatto =
##      nemico -60% HP (+5000 se ucciso), player -33% energia, barile sulla
##      cella INNESCATO; macerie svaniscono; evento chiude (events_left 0).
##   F. ROLLBACK: BARRELS_ENABLED=false -> 0 barili; QUAKE_ENABLED=false ->
##      0 eventi.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const H = preload("res://scripts/entities/MazeHazards.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []
var test_enemy = null


func _ready() -> void:
        print("[TEST] boot MainGame per barili + terremoto...")
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _next(next_phase: int) -> void:
        phase = next_phase
        phase_t = 0.0


func _center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 60.0:
                _fail("timeout globale del test (60s)")
                get_tree().quit(1)
                return
        match phase:
                0:
                        if phase_t > 0.1:
                                _phaseA_constants()
                                _next(1)
                1:
                        if main == null or not main.is_node_ready():
                                return
                        if phase_t > 1.5:
                                _phaseB_generation()
                                _next(2)
                2:
                        _phaseC_explosion()
                        _next(3)
                3:
                        _phaseD_chain()
                        _next(4)
                4:
                        _phaseE_quake()
                        _next(5)
                5:
                        _phaseF_rollback()
                        _finish()


# ===========================================================================
# A — COSTANTI
# ===========================================================================
func _phaseA_constants() -> void:
        var barrel_cases: Dictionary = {
                1: 0, 3: 0, 4: 2, 9: 2, 10: 3, 15: 3, 16: 4,
                21: 4, 22: 5, 28: 6, 40: 6, 68: 6,
        }
        for lvl in barrel_cases:
                var got: int = C.barrel_count_for_level(lvl)
                if got != barrel_cases[lvl]:
                        _fail("A: barrel_count_for_level(%d) = %d, atteso %d"
                                        % [lvl, got, barrel_cases[lvl]])
        _ok("A: curva barrel_count_for_level (grace 4, 2 base, +1/6, cap 6)")
        var ev_cases: Dictionary = {1: 0, 5: 0, 6: 1, 19: 1, 20: 2, 68: 2}
        for lvl in ev_cases:
                var got: int = C.quake_events_for_level(lvl)
                if got != ev_cases[lvl]:
                        _fail("A: quake_events_for_level(%d) = %d, atteso %d"
                                        % [lvl, got, ev_cases[lvl]])
        var bd_cases: Dictionary = {1: 4, 6: 5, 12: 6, 30: 9, 60: 10, 68: 10}
        for lvl in bd_cases:
                var got: int = C.quake_boulder_count(lvl)
                if got != bd_cases[lvl]:
                        _fail("A: quake_boulder_count(%d) = %d, atteso %d"
                                        % [lvl, got, bd_cases[lvl]])
        _ok("A: terremoto: eventi per livello + massi per evento")
        # rollback dei due flag (sul calcolo)
        C.BARRELS_ENABLED = false
        if C.barrel_count_for_level(12) != 0:
                _fail("A: BARRELS_ENABLED=false non azzera i barili")
        C.BARRELS_ENABLED = true
        C.QUAKE_ENABLED = false
        if C.quake_events_for_level(12) != 0:
                _fail("A: QUAKE_ENABLED=false non azzera gli eventi")
        C.QUAKE_ENABLED = true
        _ok("A: rollback BARRELS_ENABLED / QUAKE_ENABLED")


# ===========================================================================
# B — GENERAZIONE (livello 12: 3 barili)
# ===========================================================================
func _phaseB_generation() -> void:
        main.is_paused = true
        for item in main.collectibles_node.get_children():
                item.queue_free()
        main.start_level(12)
        # TASK 38 (spawn guard): il player nasce con 3s di immortalita' —
        # azzerata perche' le fasi C/E verificano i DANNI reali di barili
        # e massi su un player vulnerabile.
        main.player.spawn_guard_ms = 0
        test_enemy = null
        for e in main.spawner.enemies:
                if not e.is_dead():
                        if test_enemy == null:
                                test_enemy = e
                        else:
                                # gli ALTRI nemici via: l'esplosione del barile
                                # uccide tutto cio' che e' nel raggio e il
                                # punteggio atteso dev'essere deterministico
                                e.take_damage(99999)
        var hz = main.hazards
        var nb: int = hz.count_by_type(H.HazardType.BARREL)
        if nb != 3:
                _fail("B: barili al livello 12 = %d, attesi 3" % nb)
        else:
                _ok("B: 3 barili generati al livello 12")
        for h in hz.hazard_list:
                if h["type"] != H.HazardType.BARREL:
                        continue
                var cell: Vector2i = h["cell"]
                if main.maze.get_cell_type(cell.x, cell.y) != C.CellType.EMPTY:
                        _fail("B: barile su cella non-EMPTY %s" % str(cell))
                if max(absi(cell.x - 1), absi(cell.y - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                        _fail("B: barile troppo vicino allo spawn %s" % str(cell))
                if not main._collectible_cell_free(cell.x, cell.y):
                        _fail("B: barile su collectible %s" % str(cell))
        # terremoto armato: 1 evento, timer nella finestra
        if hz.quake_events_left != 1:
                _fail("B: eventi terremoto = %d, atteso 1" % hz.quake_events_left)
        elif hz.quake_state != H.QuakeState.INACTIVE:
                _fail("B: terremoto non INACTIVE alla generazione")
        elif hz.quake_timer_ms < float(C.QUAKE_FIRST_MIN_MS) \
                        or hz.quake_timer_ms > float(C.QUAKE_FIRST_MAX_MS):
                _fail("B: timer terremoto fuori finestra (%.0f)" % hz.quake_timer_ms)
        else:
                _ok("B: terremoto armato (1 evento, timer %.0fs)"
                                % (hz.quake_timer_ms / 1000.0))


func _find_barrel() -> Dictionary:
        return main.hazards.find_first(H.HazardType.BARREL)


func _shoot_cell(cell: Vector2i) -> void:
        var p: CharacterBody2D = main.player
        p.projectiles.clear()
        p.projectiles.append({"pos": _center(cell.x, cell.y), "active": true})
        main.hazards.update_hazards(16.0, main.maze)
        p.projectiles.clear()


func _move_barrel(h: Dictionary, cell: Vector2i) -> void:
        h["cell"] = cell
        if h["sprite"] != null:
                h["sprite"].position = _center(cell.x, cell.y)


func _find_empty_pair() -> Vector2i:
        ## due celle EMPTY adiacenti orizzontali lontane dallo spawn
        for r in range(2, 14):
                for c in range(2, 27):
                        if main.maze.get_cell_type(c, r) == C.CellType.EMPTY \
                                        and main.maze.get_cell_type(c + 1, r) == C.CellType.EMPTY \
                                        and max(absi(c - 1), absi(r - 1)) >= 3:
                                return Vector2i(c, r)
        return Vector2i(5, 5)


# ===========================================================================
# C — ESPLOSIONE
# ===========================================================================
func _phaseC_explosion() -> void:
        var hz = main.hazards
        var p: CharacterBody2D = main.player
        var h: Dictionary = _find_barrel()
        if h.is_empty() or test_enemy == null:
                _fail("C: precondizioni mancanti (barile/nemico)")
                return
        var cell: Vector2i = h["cell"]
        # nemico ADIACENTE al barile (dentro il raggio di 100px)
        test_enemy.position = _center(cell.x + 1, cell.y)
        test_enemy.health = test_enemy.max_health
        # player LONTANO (spawn): fuori dal raggio
        p.set_position_abs(_center(1, 1).x, _center(1, 1).y)
        p.damage_timer = 0
        p.energy = p.max_energy
        var score_before: int = p.score
        var e_before: int = p.energy
        _shoot_cell(cell)
        if hz.count_by_type(H.HazardType.BARREL) != 2:
                _fail("C: il barile non e' stato rimosso dall'esplosione")
        elif not test_enemy.is_dead():
                _fail("C: nemico adiacente al barile non ucciso")
        elif p.score != score_before + C.BARREL_KILL_POINTS:
                _fail("C: punti kill barile %d, attesi %d"
                                % [p.score - score_before, C.BARREL_KILL_POINTS])
        elif p.energy != e_before:
                _fail("C: player lontano danneggiato dall'esplosione")
        else:
                _ok("C: esplosione = nemico ucciso (+%d), player lontano illeso"
                                % C.BARREL_KILL_POINTS)
        # player VICINO al secondo barile: -33% energia
        var h2: Dictionary = _find_barrel()
        if h2.is_empty():
                _fail("C: secondo barile mancante per il test danno")
                return
        var cell2: Vector2i = h2["cell"]
        # player a 1 cella di distanza (64px <= raggio 100px), grounded
        p.set_position_abs(_center(cell2.x + 1, cell2.y).x, _center(cell2.x + 1, cell2.y).y)
        p.damage_timer = 0
        p.jump_timer = 0
        p.energy = p.max_energy
        e_before = p.energy
        _shoot_cell(cell2)
        var expect_dmg: int = maxi(1, int(round(p.max_energy * C.BARREL_PLAYER_DAMAGE_PCT)))
        if p.energy != e_before - expect_dmg:
                _fail("C: danno player esplosione %d, atteso %d"
                                % [e_before - p.energy, expect_dmg])
        else:
                _ok("C: player nel raggio = -%d energia (salto/ghost salvano)"
                                % expect_dmg)


# ===========================================================================
# D — CATENA
# ===========================================================================
func _phaseD_chain() -> void:
        var hz = main.hazards
        var p: CharacterBody2D = main.player
        # restano 1 barile dal livello + ricreo una coppia controllata:
        # sposto il barile superstite e ne clono uno vicino spostando una
        # copia del dizionario con un secondo sprite.
        var h1: Dictionary = _find_barrel()
        if h1.is_empty():
                _fail("D: nessun barile per il test catena")
                return
        var pair: Vector2i = _find_empty_pair()
        _move_barrel(h1, pair)
        # secondo barile "manuale": duplica la struttura
        var h2: Dictionary = h1.duplicate(true)
        var spr: Sprite2D = main.hazards._make_sprite(
                "res://assets/sprites/hazards/barrel.png", Vector2i(pair.x + 1, pair.y), 54.0)
        h2["cell"] = Vector2i(pair.x + 1, pair.y)
        h2["sprite"] = spr
        h2["state"] = H.BarrelState.INTACT
        h2["timer_ms"] = 0.0
        main.hazards.hazard_list.append(h2)
        # player lontano
        p.set_position_abs(_center(1, 1).x, _center(1, 1).y)
        p.damage_timer = 0
        p.energy = p.max_energy
        # spara al primo: il secondo deve andare in FUSE e poi esplodere
        _shoot_cell(pair)
        if h2["state"] != H.BarrelState.FUSE:
                _fail("D: il barile vicino non e' andato in FUSE (catena rotta)")
                return
        _ok("D: reazione a catena innescata (barile vicino in FUSE)")
        # attende la miccia (220ms) + margine
        for _i in 20:
                main.hazards.update_hazards(30.0, main.maze)
        if main.hazards.hazard_list.has(h2):
                _fail("D: il secondo barile non e' esploso dopo il fuse")
        else:
                _ok("D: secondo barile esploso dopo %dms di miccia"
                                % C.BARREL_CHAIN_DELAY_MS)


# ===========================================================================
# E — TERREMOTO
# ===========================================================================
func _phaseE_quake() -> void:
        var hz = main.hazards
        var p: CharacterBody2D = main.player
        # forza il timer: telegrafo
        hz.quake_timer_ms = 1.0
        hz.update_hazards(16.0, main.maze)
        if hz.quake_state != H.QuakeState.TELEGRAPH:
                _fail("E: telegrafo non partito (stato %d)" % hz.quake_state)
                return
        _ok("E: telegrafo attivo (rombo + scrollamento)")
        # avanza il telegrafo (1.5s)
        for _i in 12:
                hz.update_hazards(150.0, main.maze)
        if hz.quake_state != H.QuakeState.DROPPING:
                _fail("E: fase DROPPING non raggiunta")
                return
        var nb: int = hz.boulder_list.size()
        if nb != C.quake_boulder_count(12):
                _fail("E: massi = %d, attesi %d" % [nb, C.quake_boulder_count(12)])
        else:
                _ok("E: %d massi in caduta con marker crepa" % nb)
        # prende il primo masso: nemico + player + barile sulla cella
        var b: Dictionary = hz.boulder_list[0]
        var cell: Vector2i = b["cell"]
        if test_enemy != null and not test_enemy.is_dead():
                test_enemy.position = _center(cell.x, cell.y)
                test_enemy.health = test_enemy.max_health
        p.set_position_abs(_center(cell.x, cell.y).x, _center(cell.x, cell.y).y)
        p.damage_timer = 0
        p.jump_timer = 0
        p.energy = p.max_energy
        var e_before: int = p.energy
        var eh_before: int = test_enemy.health if test_enemy != null else 0
        var score_before: int = p.score
        # piazza un barile su un ALTRO massO e verifica l'innesco
        var b2: Dictionary = hz.boulder_list[1]
        var h_barrel: Dictionary = _find_barrel()
        if not h_barrel.is_empty() and hz.boulder_list.size() > 1:
                _move_barrel(h_barrel, b2["cell"])
        # guida il primo masso fino all'impatto (salta delay e mark)
        b["delay_ms"] = 0.0
        b["timer_ms"] = 1.0
        b["state"] = 1
        if b["sprite"] != null:
                b["sprite"].queue_free()
                b["sprite"] = null
        b["fall_sprite"] = main.hazards._make_sprite(
                "res://assets/sprites/hazards/boulder.png", cell, 58.0)
        b["fall_from"] = _center(cell.x, cell.y) + Vector2(0.0, -420.0)
        b["fall_sprite"].position = b["fall_from"]
        hz.update_hazards(16.0, main.maze)
        if b["state"] != 2:
                _fail("E: impatto non registrato (stato %d)" % b["state"])
                return
        var e_dmg: int = maxi(1, int(round(
                        test_enemy.get_max_health() * C.QUAKE_ENEMY_DAMAGE_PCT))) \
                        if test_enemy != null else 0
        var p_dmg: int = maxi(1, int(round(p.max_energy * C.QUAKE_PLAYER_DAMAGE_PCT)))
        if test_enemy != null and not test_enemy.is_dead() \
                        and test_enemy.health != eh_before - e_dmg:
                _fail("E: danno nemico masso %d, atteso %d"
                                % [eh_before - test_enemy.health, e_dmg])
        elif p.energy != e_before - p_dmg:
                _fail("E: danno player masso %d, atteso %d"
                                % [e_before - p.energy, p_dmg])
        else:
                _ok("E: impatto = nemico -%d HP, player -%d energia" % [e_dmg, p_dmg])
        if not h_barrel.is_empty() and hz.hazard_list.has(h_barrel) \
                        and h_barrel["state"] == H.BarrelState.INTACT:
                _fail("E: barile colpito dal masso non innescato")
        elif not h_barrel.is_empty() and hz.hazard_list.has(h_barrel):
                _ok("E: masso su barile = innesco (combo)")
        # macerie: svaniscono e l'evento si chiude
        for _i in 400:
                hz.update_hazards(50.0, main.maze)
                if hz.quake_state == H.QuakeState.INACTIVE \
                                and hz.boulder_list.is_empty():
                        break
        if not hz.boulder_list.is_empty():
                _fail("E: massi/macerie non svaniti")
        elif hz.quake_state != H.QuakeState.INACTIVE:
                _fail("E: evento terremoto non concluso")
        elif hz.quake_events_left != 0:
                _fail("E: eventi residui = %d, atteso 0" % hz.quake_events_left)
        else:
                _ok("E: macerie svanite, evento concluso (events_left 0)")


# ===========================================================================
# F — ROLLBACK
# ===========================================================================
func _phaseF_rollback() -> void:
        C.BARRELS_ENABLED = false
        main.start_level(12)
        if main.hazards.count_by_type(H.HazardType.BARREL) != 0:
                _fail("F: BARRELS_ENABLED=false ma barili generati")
        else:
                _ok("F: rollback barili — nessun barile")
        C.BARRELS_ENABLED = true
        C.QUAKE_ENABLED = false
        main.start_level(20)
        if main.hazards.quake_events_left != 0:
                _fail("F: QUAKE_ENABLED=false ma eventi programmati")
        else:
                _ok("F: rollback terremoto — nessun evento")
        C.QUAKE_ENABLED = true


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] TUTTI I TEST BARILI + TERREMOTO SUPERATI")
                get_tree().quit(0)
        else:
                print("[TEST] %d TEST BARILI + TERREMOTO FALLITI:" % failures.size())
                for f in failures:
                        print("  - ", f)
                get_tree().quit(1)

## test_hazards.gd — Test funzionale runtime (headless) degli HAZARD
## AMBIENTALI del labirinto (Task 30 + Task 34):
##   A. COSTANTI: hazard_count_for_level — grace level 4, +1 ogni 3 livelli,
##      cap 4 per tipo (TASK 34: era 5); rollback HAZARDS_ENABLED = false.
##   B. GENERAZIONE: start_level(7) -> 2 hazard per tipo (sabbie/ganasce/
##      voragini; muri >= 1 se candidati scarsi), celle EMPTY per il
##      pavimento e WALL tra due corridoi per i muri, distanza minima dallo
##      spawn, gap Manhattan >= 2 tra hazard, niente hazard su collectible,
##      registro dynamic_walls coerente (muro aperto = false).
##   C. MURO DI ROCCIA: ciclo OPEN->WARN->CLOSED->OPEN guidato a step;
##      is_wall() true da chiuso / false da aperto; player nella cella alla
##      chiusura = -66% energia max + held_by_wall; nemico = -33% HP max +
##      held_by_wall; nemico ucciso dal muro = +10000 al player vicino;
##      riapertura = flag rilasciati. TASK 34: nemico a META' TRANSITO verso
##      la cella che si chiude si FERMA e rientra (il muro chiuso blocca
##      anche i nemici, mai compenetrazione nella roccia).
##   D. GANASCE: cattura player grounded = -33% energia max + held_by_trap;
##      mash accorcia la tenuta; scadenza = rilascio + DISATTIVAZIONE
##      PERMANENTE (TASK 34: SPRUNG, niente riarmo — il player puo' essere
##      colpito UNA SOLA volta); PROIETTILE nella cella = scatto a vuoto
##      (disattivata anche cosi', proiettile consumato).
##   E. VORAGINE: DORMANT->CRACK (sprite crepa) ->OPEN (sprite voragine);
##      player grounded sulla cella aperta = vita persa (fall_into_chasm).
##   F. SABBIE MOBILI: hazard_slow 0.5 sulla cella; stivali alati
##      (permanent_speed_boost) annullano il rallentamento.
##   G. ROLLBACK GLOBALE: HAZARDS_ENABLED = false -> generate() non produce
##      nulla e il registro dynamic_walls resta vuoto.
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
        print("[TEST] boot MainGame per hazard ambientali...")
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


func _cell_center(c: int, r: int) -> Vector2:
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
                        _phaseC_rock_wall()
                        _next(3)
                3:
                        _phaseD_trap()
                        _next(4)
                4:
                        _phaseE_chasm()
                        _next(5)
                5:
                        _phaseF_quicksand()
                        _next(6)
                6:
                        _phaseG_rollback()
                        _finish()


# ===========================================================================
# A — COSTANTI
# ===========================================================================
func _phaseA_constants() -> void:
        var cases: Dictionary = {
                1: 0, 2: 0, 3: 0, 4: 1, 5: 1, 6: 1, 7: 2, 9: 2,
                10: 3, 13: 4, 16: 4, 19: 4, 40: 4, 68: 4,
        }
        for lvl in cases:
                var got: int = C.hazard_count_for_level(lvl)
                if got != cases[lvl]:
                        _fail("A: hazard_count_for_level(%d) = %d, atteso %d"
                                        % [lvl, got, cases[lvl]])
        _ok("A: curva hazard_count_for_level (grace 4, +1/3 livelli, cap 4 — Task 34)")
        # Rollback del solo flag: conteggio a zero per ogni livello.
        C.HAZARDS_ENABLED = false
        if C.hazard_count_for_level(30) != 0:
                _fail("A: HAZARDS_ENABLED=false non azzera il conteggio")
        C.HAZARDS_ENABLED = true
        _ok("A: rollback HAZARDS_ENABLED")


# ===========================================================================
# B — GENERAZIONE (livello 7: 2 per tipo)
# ===========================================================================
func _phaseB_generation() -> void:
        # Congela il loop: da qui solo chiamate dirette (pattern test reliquie).
        main.is_paused = true
        # Item a terra via (medikit/pozione altererebbero l'energia).
        for item in main.collectibles_node.get_children():
                item.queue_free()
        main.start_level(7)
        # Nemico di test: il PRIMO vivo del livello APPENA generato
        # (start_level rigenera lo spawner: selezionarlo prima puntava a
        # nemici freed e i test C saltavano in silenzio).
        test_enemy = null
        for e in main.spawner.enemies:
                if not e.is_dead():
                        test_enemy = e
                        break
        var hz = main.hazards
        var expected: int = C.hazard_count_for_level(7)
        if expected != 2:
                _fail("B: atteso 2 hazard/tipo al livello 7, costante = %d" % expected)
        for t2 in [H.HazardType.QUICKSAND, H.HazardType.TRAP, H.HazardType.CHASM]:
                var n: int = hz.count_by_type(t2)
                if n != 2:
                        _fail("B: hazard pavimento tipo %d = %d, atteso 2" % [t2, n])
        var nw: int = hz.count_by_type(H.HazardType.ROCK_WALL)
        if nw < 1:
                _fail("B: nessun muro di roccia generato al livello 7")
        else:
                _ok("B: generazione livello 7 — %d sabbie, %d ganasce, %d voragini, %d muri"
                                % [hz.count_by_type(H.HazardType.QUICKSAND),
                                        hz.count_by_type(H.HazardType.TRAP),
                                        hz.count_by_type(H.HazardType.CHASM), nw])
        # Vincoli di placement su TUTTI gli hazard.
        for h in hz.hazard_list:
                var cell: Vector2i = h["cell"]
                if max(absi(cell.x - 1), absi(cell.y - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                        _fail("B: hazard %s troppo vicino allo spawn (%s)"
                                        % [h["type"], str(cell)])
                if h["type"] == H.HazardType.ROCK_WALL:
                        if main.maze.get_cell_type(cell.x, cell.y) != C.CellType.WALL:
                                _fail("B: muro di roccia su cella non-WALL %s" % str(cell))
                else:
                        if main.maze.get_cell_type(cell.x, cell.y) != C.CellType.EMPTY:
                                _fail("B: hazard pavimento su cella non-EMPTY %s" % str(cell))
                        if not main._collectible_cell_free(cell.x, cell.y):
                                _fail("B: hazard pavimento su cella collectible %s" % str(cell))
        # Gap minimo tra hazard (Manhattan >= 2).
        var list: Array = hz.hazard_list
        for i in list.size():
                for j in range(i + 1, list.size()):
                        var a: Vector2i = list[i]["cell"]
                        var b: Vector2i = list[j]["cell"]
                        if absi(a.x - b.x) + absi(a.y - b.y) < C.HAZARD_MIN_GAP:
                                _fail("B: hazard troppo vicini %s / %s" % [str(a), str(b)])
        _ok("B: placement (distanza spawn, celle valide, gap %d)" % C.HAZARD_MIN_GAP)
        # Registro dynamic_walls: ogni muro presente, APERTO (false).
        var walls: int = 0
        for h in list:
                if h["type"] == H.HazardType.ROCK_WALL:
                        walls += 1
                        var key: String = "%d,%d" % [h["cell"].x, h["cell"].y]
                        if not main.maze.dynamic_walls.has(key):
                                _fail("B: muro %s mancante nel registro dynamic_walls" % key)
                        elif main.maze.dynamic_walls[key] != false:
                                _fail("B: muro %s registrato CHIUSO alla generazione" % key)
                        elif main.maze.is_wall(h["cell"].x, h["cell"].y):
                                _fail("B: muro %s aperto ma is_wall=true" % key)
        if walls > 0:
                _ok("B: registro dynamic_walls coerente (%d muri, tutti aperti)" % walls)


# ===========================================================================
# C — MURO DI ROCCIA: ciclo, danni, tenute, kill ambientale
# ===========================================================================
func _drive_wall_phase(hz, h: Dictionary, want_closed: bool) -> void:
        ## Avanza update_hazards a step di 100ms fino allo stato voluto
        ## (cap 100 step = 10s simulati).
        for _i in 100:
                var closed: bool = h["phase"] == H.WallPhase.CLOSED
                if closed == want_closed:
                        return
                hz.update_hazards(100.0, main.maze)


func _phaseC_rock_wall() -> void:
        var hz = main.hazards
        var h: Dictionary = hz.find_first(H.HazardType.ROCK_WALL)
        if h.is_empty():
                _fail("C: nessun muro di roccia da testare")
                return
        var cell: Vector2i = h["cell"]
        var p: CharacterBody2D = main.player
        # --- Chiusura: player dentro la cella ---
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.damage_timer = 0
        p.energy = p.max_energy
        var e_before: int = p.energy
        _drive_wall_phase(hz, h, true)
        if h["phase"] != H.WallPhase.CLOSED:
                _fail("C: il muro non raggiunge mai lo stato CLOSED")
                return
        if not main.maze.is_wall(cell.x, cell.y):
                _fail("C: is_wall=false con muro CHIUSO")
        var expect_dmg: int = maxi(1, int(round(p.max_energy * C.HAZARD_WALL_PLAYER_DAMAGE_PCT)))
        if p.energy != e_before - expect_dmg:
                _fail("C: danno player %d, atteso %d (energia %d -> %d)"
                                % [e_before - p.energy, expect_dmg, e_before, p.energy])
        elif not p.held_by_wall:
                _fail("C: player non trattenuto dal muro chiuso")
        else:
                _ok("C: chiusura su player = -%d energia + held_by_wall" % expect_dmg)
        # --- Nemico nella cella: 33% HP + held ---
        if test_enemy != null and not test_enemy.is_dead():
                test_enemy.position = _cell_center(cell.x, cell.y)
                test_enemy.health = test_enemy.max_health
                var eh_before: int = test_enemy.health
                # prima riapri, poi richiudi col nemico dentro
                _drive_wall_phase(hz, h, false)
                _drive_wall_phase(hz, h, true)
                var e_dmg: int = maxi(1, int(round(
                                test_enemy.get_max_health() * C.HAZARD_WALL_ENEMY_DAMAGE_PCT)))
                if test_enemy.health != eh_before - e_dmg:
                        _fail("C: danno nemico %d, atteso %d"
                                        % [eh_before - test_enemy.health, e_dmg])
                elif not test_enemy.held_by_wall:
                        _fail("C: nemico non trattenuto dal muro chiuso")
                else:
                        _ok("C: chiusura su nemico = -%d HP + held_by_wall" % e_dmg)
        # --- Kill ambientale: +10000 al player vivo piu' vicino ---
        if test_enemy != null and not test_enemy.is_dead():
                _drive_wall_phase(hz, h, false)
                test_enemy.position = _cell_center(cell.x, cell.y)
                test_enemy.health = 1  # un colpo solo di muro lo uccide
                var score_before: int = p.score
                _drive_wall_phase(hz, h, true)
                if not test_enemy.is_dead():
                        _fail("C: nemico a 1 HP non ucciso dal muro")
                elif p.score != score_before + C.HAZARD_WALL_KILL_POINTS:
                        _fail("C: bonus kill ambientale %d, atteso %d"
                                        % [p.score - score_before, C.HAZARD_WALL_KILL_POINTS])
                else:
                        _ok("C: kill ambientale = +%d punti" % C.HAZARD_WALL_KILL_POINTS)
        # --- Riapertura: flag rilasciati, is_wall di nuovo false ---
        p.held_by_wall = false  # reset difensivo per il confronto
        _drive_wall_phase(hz, h, false)
        if main.maze.is_wall(cell.x, cell.y):
                _fail("C: is_wall=true con muro APERTO")
        elif p.held_by_wall:
                _fail("C: held_by_wall non rilasciato alla riapertura")
        else:
                _ok("C: riapertura = passaggio libero + flag rilasciati")
        # --- TASK 34: il muro CHIUSO blocca i nemici anche a meta' transito ---
        # Nemico vivo fresco (il precedente e' stato ucciso dal test kill):
        var blocker = null
        for e in main.spawner.enemies:
                if e != null and is_instance_valid(e) and not e.is_dead() \
                                and not e.held_by_wall:
                        blocker = e
                        break
        if blocker == null:
                _fail("C: nessun nemico vivo per il test blocco muro")
                return
        # chiudi il muro, poi metti il nemico a META' TRANSITO dalla cella
        # adiacente verso la cella del muro (waypoint gia' sbloccato)
        _drive_wall_phase(hz, h, true)
        var from_cell: Vector2i = cell + (Vector2i(1, 0) if h["axis"] == "h" \
                        else Vector2i(0, 1))
        var from_center: Vector2 = _cell_center(from_cell.x, from_cell.y)
        var wall_center: Vector2 = _cell_center(cell.x, cell.y)
        blocker.position = from_center + (wall_center - from_center) * 0.25
        blocker.dx = 1 if h["axis"] == "h" else 0
        blocker.dy = 0 if h["axis"] == "h" else 1
        blocker._move_waypoint = wall_center
        blocker.held_by_wall = false
        blocker.stuck_timer = 0
        blocker.update_enemy(main.maze, Vector2i(1, 1),
                        main.player.get_pixel_pos(), [], 16.0)
        var b_cell: Vector2i = Vector2i(
                        int(blocker.position.x / 64),
                        int((blocker.position.y - 80) / 64))
        var b_dist: float = blocker.position.distance_to(from_center)
        if b_cell == cell:
                _fail("C: nemico entrato nella cella del muro CHIUSO")
        elif blocker.dx != 0 or blocker.dy != 0:
                _fail("C: transito verso il muro chiuso non abortito (dx/dy residui)")
        elif b_dist > 20.0:
                _fail("C: nemico non rientrato verso il centro di provenienza")
        else:
                _ok("C: muro chiuso blocca il nemico (abort transito + rientro)")
        # pulizia: riapri e libera il nemico di test
        _drive_wall_phase(hz, h, false)
        blocker.held_by_wall = false


# ===========================================================================
# D — GANASCE: cattura, mash, rilascio, disarmo
# ===========================================================================
func _phaseD_trap() -> void:
        var hz = main.hazards
        var h: Dictionary = hz.find_first(H.HazardType.TRAP)
        if h.is_empty():
                _fail("D: nessuna ganascia da testare")
                return
        var cell: Vector2i = h["cell"]
        var p: CharacterBody2D = main.player
        # stato pulito e ARMATA
        h["state"] = H.TrapState.ARMED
        h["holding"] = null
        hz._set_trap_sprite(h, true)
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.damage_timer = 0
        p.energy = p.max_energy
        p.jump_timer = 0
        var e_before: int = p.energy
        hz.update_hazards(16.0, main.maze)
        if h["state"] != H.TrapState.SNAPPED or h["holding"] != p:
                _fail("D: player grounded sulla ganascia non catturato")
                return
        var expect_dmg: int = maxi(1, int(round(p.max_energy * C.HAZARD_TRAP_DAMAGE_PCT)))
        if p.energy != e_before - expect_dmg:
                _fail("D: danno ganasce %d, atteso %d" % [e_before - p.energy, expect_dmg])
        elif not p.held_by_trap:
                _fail("D: player catturato ma held_by_trap=false")
        else:
                _ok("D: cattura = -%d energia + held_by_trap" % expect_dmg)
        # --- Mash: 5 pressioni = -1250ms sulla tenuta (clamp al minimo
        # applicato PRIMA del decorso del tempo del frame) ---
        var hold_before: float = float(h["hold_ms"])
        p.input_mash_count = 5
        hz.update_hazards(16.0, main.maze)
        var hold_after: float = float(h["hold_ms"])
        var expected_hold: float = maxf(C.HAZARD_TRAP_HOLD_MIN_MS,
                hold_before - C.HAZARD_TRAP_MASH_REDUCE_MS * 5) - 16.0
        if absf(hold_after - expected_hold) > 1.0:
                _fail("D: mash tenuta %.0fms, attesa %.0fms" % [hold_after, expected_hold])
        else:
                _ok("D: 5 mash = -%dms di tenuta" % (C.HAZARD_TRAP_MASH_REDUCE_MS * 5))
        # --- Scadenza: rilascio + DISATTIVAZIONE permanente (TASK 34) ---
        h["hold_ms"] = 1.0
        hz.update_hazards(16.0, main.maze)
        if h["state"] != H.TrapState.SPRUNG:
                _fail("D: ganascia non DISATTIVATA (SPRUNG) dopo la tenuta")
        elif p.held_by_trap:
                _fail("D: held_by_trap non rilasciato alla scadenza")
        else:
                _ok("D: scadenza tenuta = rilascio + disattivazione permanente")
        # --- TASK 34: il player puo' essere colpito UNA SOLA volta ---
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.damage_timer = 0
        p.jump_timer = 0
        var e_stay: int = p.energy
        for _i in 10:
                hz.update_hazards(16.0, main.maze)
        if p.energy != e_stay:
                _fail("D: ganascia scattata ha colpito una seconda volta")
        elif p.held_by_trap:
                _fail("D: ganascia scattata ha ricolto il player")
        elif h["state"] != H.TrapState.SPRUNG:
                _fail("D: ganascia scattata non resta SPRUNG")
        else:
                _ok("D: ganascia scattata = innocua (colpo unico sul player)")
        # --- Disarmo da proiettile: scatto a vuoto = DISATTIVATA (Task 34) ---
        h["state"] = H.TrapState.ARMED
        h["holding"] = null
        hz._set_trap_sprite(h, true)
        p.projectiles.clear()
        p.projectiles.append({"pos": _cell_center(cell.x, cell.y), "active": true})
        hz.update_hazards(16.0, main.maze)
        if h["state"] != H.TrapState.SPRUNG:
                _fail("D: proiettile sulla ganascia non la disattiva")
        elif p.projectiles[0]["active"] != false:
                _fail("D: proiettile del disarmo non consumato")
        elif p.held_by_trap:
                _fail("D: disarmo a vuoto ma player trattenuto")
        else:
                _ok("D: proiettile = scatto a vuoto (disattivata, colpo consumato)")
        p.projectiles.clear()


# ===========================================================================
# E — VORAGINE: telegrafo, apertura, caduta
# ===========================================================================
func _phaseE_chasm() -> void:
        var hz = main.hazards
        var h: Dictionary = hz.find_first(H.HazardType.CHASM)
        if h.is_empty():
                _fail("E: nessuna voragine da testare")
                return
        var cell: Vector2i = h["cell"]
        var p: CharacterBody2D = main.player
        # --- Telegrafo: DORMANT -> CRACK (sprite crepa) ---
        h["state"] = H.ChasmState.DORMANT
        h["timer_ms"] = 1.0
        if h["sprite"] != null:
                h["sprite"].queue_free()
                h["sprite"] = null
        hz.update_hazards(16.0, main.maze)
        if h["state"] != H.ChasmState.CRACK or h["sprite"] == null:
                _fail("E: telegrafo crepa non partito (stato %s)"
                                % ("CRACK" if h["state"] == H.ChasmState.CRACK else "altro"))
                return
        _ok("E: telegrafo = crepa visibile + rumble")
        # --- Apertura dopo il telegrafo ---
        h["timer_ms"] = 1.0
        hz.update_hazards(16.0, main.maze)
        if h["state"] != H.ChasmState.OPEN:
                _fail("E: voragine non aperta dopo il telegrafo")
                return
        _ok("E: apertura permanente dopo %.1fs" % (C.HAZARD_CHASM_TELEGRAPH_MS / 1000.0))
        # --- Caduta: player grounded sulla cella aperta perde una vita ---
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.jump_timer = 0
        p.energy = p.max_energy
        var lives_before: int = p.lives
        hz.update_hazards(16.0, main.maze)
        if p.lives != lives_before - 1:
                _fail("E: player sulla voragine aperta non ha perso una vita (%d -> %d)"
                                % [lives_before, p.lives])
        else:
                _ok("E: caduta in voragine = -1 vita + respawn")
        # --- Il salto protegge ---
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.jump_timer = 10
        p.energy = p.max_energy
        lives_before = p.lives
        hz.update_hazards(16.0, main.maze)
        if p.lives != lives_before:
                _fail("E: player in salto caduto nella voragine")
        else:
                _ok("E: salto sopra la voragine = incolume")
        p.jump_timer = 0


# ===========================================================================
# F — SABBIE MOBILI: rallentamento + stivali
# ===========================================================================
func _phaseF_quicksand() -> void:
        var hz = main.hazards
        var h: Dictionary = hz.find_first(H.HazardType.QUICKSAND)
        if h.is_empty():
                _fail("F: nessuna sabbia mobile da testare")
                return
        var cell: Vector2i = h["cell"]
        var p: CharacterBody2D = main.player
        p.set_position_abs(_cell_center(cell.x, cell.y).x, _cell_center(cell.x, cell.y).y)
        p.jump_timer = 0
        p.held_by_trap = false
        p.held_by_wall = false
        hz.update_hazards(16.0, main.maze)
        if absf(p.hazard_slow - C.HAZARD_QUICKSAND_SLOW) > 0.001:
                _fail("F: hazard_slow %.2f, atteso %.2f" % [p.hazard_slow, C.HAZARD_QUICKSAND_SLOW])
        else:
                _ok("F: sabbie mobili = slow %.0f%%" % (C.HAZARD_QUICKSAND_SLOW * 100))
        # Stivali alati: il rallentamento e' ignorato.
        p.permanent_speed_boost = true
        hz.update_hazards(16.0, main.maze)
        if absf(p.hazard_slow - 1.0) > 0.001:
                _fail("F: stivali alati non annullano il slow (%.2f)" % p.hazard_slow)
        else:
                _ok("F: stivali alati = slow annullato")
        p.permanent_speed_boost = false
        # Fuori dalla cella: slow rimosso.
        p.set_position_abs(_cell_center(1, 1).x, _cell_center(1, 1).y)
        hz.update_hazards(16.0, main.maze)
        if absf(p.hazard_slow - 1.0) > 0.001:
                _fail("F: slow non rimosso fuori dalla sabbia (%.2f)" % p.hazard_slow)
        else:
                _ok("F: fuori dalla sabbia = velocita' normale")


# ===========================================================================
# G — ROLLBACK GLOBALE
# ===========================================================================
func _phaseG_rollback() -> void:
        # TASK 31: barili e terremoto sono sistemi SEPARATI (flag propri):
        # per il rollback degli hazard del Task 30 si spegne anche BARRELS
        # perche' i barili vivono nella stessa hazard_list.
        C.HAZARDS_ENABLED = false
        C.BARRELS_ENABLED = false
        main.start_level(7)
        if not main.hazards.hazard_list.is_empty():
                _fail("G: HAZARDS_ENABLED=false ma hazard generati comunque")
        elif not main.maze.dynamic_walls.is_empty():
                _fail("G: HAZARDS_ENABLED=false ma dynamic_walls non vuoto")
        else:
                _ok("G: rollback globale — nessun hazard, registro pulito")
        C.HAZARDS_ENABLED = true
        C.BARRELS_ENABLED = true


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] TUTTI I TEST HAZARD SUPERATI")
                get_tree().quit(0)
        else:
                print("[TEST] %d TEST HAZARD FALLITI:" % failures.size())
                for f in failures:
                        print("  - ", f)
                get_tree().quit(1)

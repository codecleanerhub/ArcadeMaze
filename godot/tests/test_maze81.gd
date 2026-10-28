## test_maze81.gd — TASK 81: test runtime FANTASMI LENZUOLO + CELLE ZOMBIE.
##
## FANTASMI (MazeGhosts):
##   F1. pool di 4 fantasmi, 3 apparizioni ciascuno
##   F2. attraversamenti totali dopo lunghissima simulazione = 12 (4x3),
##       nessun fantasma supera le 3 apparizioni
##   F3. i 3 muri usati da ogni fantasma sono DIVERSI ("respawn da un
##       altro muro")
##   F4. simultanei su schermo MAI oltre 4 (cap); valore 4 raggiunto al
##       livello alto (probabilita' crescente)
##   F5. cap al livello 1 resta quasi sempre basso (<= 2 tolleranza)
##
## CELLE ZOMBIE (ZombieCells):
##   Z1. numero celle per livello: 1 (L1), 2 (L4), 3 (L7), mai oltre 3
##   Z2. celle su muri con corridoio adiacente, lontane dallo spawn,
##       ben distanziate (>= 4 Manhattan, target 8)
##   Z3. determinismo: stesso livello -> stesse celle (seed, per il
##       continue = sessione esatta)
##   Z4. macchina a fasi: IDLE -> EMERGE -> OUT (5s esatti) -> RETRACT
##       -> IDLE
##   Z5. danno: player nella cella corridoio davanti alle braccia estese
##       prende 20% dell'energia massima (arrotondato, min 1); player
##       fuori zona non prende nulla; braccia ritratte non fanno danno
##
## Uso: Godot --headless --path . res://tests/test_maze81.tscn
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MazeScript = preload("res://scripts/core/Maze.gd")
const MazeGhostsScript = preload("res://scripts/entities/MazeGhosts.gd")
const ZombieCellsScript = preload("res://scripts/entities/ZombieCells.gd")

var failures: Array = []
var checks: int = 0


## Stub player per il test del danno (duck-typing: position/max_energy/
## take_hazard_damage). Simula anche l'invulnerabilita' post-tocco (~1s,
## damage_timer del Player reale) per contare i TOCCHI, non i frame.
class StubPlayer:
        extends RefCounted
        var position: Vector2 = Vector2.ZERO
        var max_energy: int = 5
        var energy: int = 5
        var hits: int = 0
        var last_dmg: int = 0
        var invuln_ms: float = 0.0

        func tick(delta_ms: float) -> void:
                invuln_ms = maxf(0.0, invuln_ms - delta_ms)

        func take_hazard_damage(dmg: int) -> void:
                if invuln_ms > 0.0:
                        return
                hits += 1
                last_dmg = dmg
                energy -= dmg
                invuln_ms = 1000.0


func ok(cond: bool, label: String) -> void:
        checks += 1
        if cond:
                print("[TEST-81] OK: ", label)
        else:
                failures.append(label)
                print("[TEST-81] FAIL: ", label)


## Cella muro+corridoio con facing, presa da ZombieCells._collect_candidates
## (reimplementata qui in forma ridotta per il check Z2).
func has_empty_neighbor(maze: Node, c: int, r: int) -> bool:
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                var nc: int = c + d.x
                var nr: int = r + d.y
                if nc < 0 or nc >= C.MAZE_COLS or nr < 0 or nr >= C.MAZE_ROWS:
                        continue
                if not maze.is_wall(nc, nr):
                        return true
        return false


func _ready() -> void:
        print("[TEST-81] ==== TEST FANTASMI + CELLE ZOMBIE (TASK 81) ====")

        # ----------------------------------------------------------------
        # FANTASMI — simulazione lunga al livello 12 (intervalli compressi,
        # cap simultaneo alto) e al livello 1 (cap basso).
        # ----------------------------------------------------------------
        var maze: Node = MazeScript.new()
        add_child(maze)

        # --- livello 12: il budget si esaurisce del tutto ---
        maze.generate(12)
        var ghosts: Node = MazeGhostsScript.new()
        add_child(ghosts)
        ghosts.generate(12, maze)
        ok(ghosts.ghost_count() == C.GHOST_POOL_SIZE, "F1 pool di %d fantasmi" % C.GHOST_POOL_SIZE)
        ok(ghosts.total_appearances_left() == C.GHOST_POOL_SIZE * C.GHOST_MAX_APPEARANCES,
                        "F1 budget iniziale = 4x3 = 12 apparizioni")
        ok(ghosts.run_count() > 0, "F2 il labirinto offre segmenti muro (%d)" % ghosts.run_count())

        var max_simul_12: int = 0
        var max_distinct_out: int = 0
        # 15 minuti di gioco simulati a step da ~16.7ms
        var steps: int = int(900000.0 / 16.6667)
        for i in range(steps):
                ghosts.update_ghosts(16.6667)
                max_simul_12 = maxi(max_simul_12, ghosts.active_count())
        ok(ghosts.total_appearances_left() == 0,
                        "F2 budget esaurito dopo 15 min simulati (residuo %d)" % ghosts.total_appearances_left())
        ok(max_simul_12 <= C.GHOST_MAX_SIMULTANEOUS,
                        "F4 simultanei mai oltre %d (max visto %d)" % [C.GHOST_MAX_SIMULTANEOUS, max_simul_12])
        ok(max_simul_12 >= 2, "F4 al livello 12 i fantasmi si sovrappongono (max %d >= 2)" % max_simul_12)
        var colors_seen: Array = []
        for col in ["white", "red", "green"]:
                var used: Array = ghosts.used_run_keys_of(col)
                colors_seen.append(used.size())
                ok(used.size() <= C.GHOST_MAX_APPEARANCES,
                                "F2 fantasma %s: max %d apparizioni (usate %d)" % [col, C.GHOST_MAX_APPEARANCES, used.size()])
                var distinct: bool = true
                for k in used:
                        if used.count(k) > 1:
                                distinct = false
                ok(distinct or used.is_empty(), "F3 fantasma %s: muri tutti diversi" % col)
        max_distinct_out = colors_seen.max()

        # --- livello 1: il cap simultaneo resta contenuto ---
        maze.generate(1)
        ghosts.generate(1, maze)
        var max_simul_1: int = 0
        steps = int(240000.0 / 16.6667)
        for i in range(steps):
                ghosts.update_ghosts(16.6667)
                max_simul_1 = maxi(max_simul_1, ghosts.active_count())
        ok(max_simul_1 <= 2, "F5 al livello 1 simultanei <= 2 (max visto %d)" % max_simul_1)

        # ----------------------------------------------------------------
        # CELLE ZOMBIE
        # ----------------------------------------------------------------
        var zcells: Node = ZombieCellsScript.new()
        add_child(zcells)

        # --- Z1: numeri per livello ---
        maze.generate(1)
        zcells.generate(1, maze)
        var n_l1: int = zcells.cell_count()
        maze.generate(4)
        zcells.generate(4, maze)
        var n_l4: int = zcells.cell_count()
        maze.generate(7)
        zcells.generate(7, maze)
        var n_l7: int = zcells.cell_count()
        ok(n_l1 == 1, "Z1 livello 1 -> 1 cella (%d)" % n_l1)
        ok(n_l4 == 2, "Z1 livello 4 -> 2 celle (%d)" % n_l4)
        ok(n_l7 == 3, "Z1 livello 7 -> 3 celle (%d)" % n_l7)
        ok(C.zombie_cells_for_level(50) == 3, "Z1 cap massimo 3 anche a livello 50")

        # --- Z2: vincoli di piazzamento (sul livello 7 rigenerato) ---
        maze.generate(7)
        zcells.generate(7, maze)
        var positions: Array = zcells.cell_positions()
        var constraints_ok: bool = true
        var min_pair_dist: int = 999
        for p in positions:
                if not maze.is_wall(p.x, p.y):
                        constraints_ok = false
                if not has_empty_neighbor(maze, p.x, p.y):
                        constraints_ok = false
                if absi(p.x - 1) + absi(p.y - 1) < C.ZOMBIE_CELLS_MIN_DIST_SPAWN:
                        constraints_ok = false
        for i in range(positions.size()):
                for j in range(i + 1, positions.size()):
                        var d: int = absi(positions[i].x - positions[j].x) \
                                        + absi(positions[i].y - positions[j].y)
                        min_pair_dist = mini(min_pair_dist, d)
        ok(constraints_ok, "Z2 celle su muro+corridoio, lontane dallo spawn")
        ok(min_pair_dist >= 4, "Z2 distanza minima tra celle >= 4 (reale %d)" % min_pair_dist)

        # --- Z3: determinismo (il continue ripristina la griglia con
        # restore_state: stessa griglia + stesso seed -> stesse celle) ---
        var snapshot: Dictionary = maze.serialize_state()
        var pos_a: Array = zcells.cell_positions().duplicate()
        maze.restore_state(snapshot)
        zcells.generate(7, maze)
        var pos_b: Array = zcells.cell_positions().duplicate()
        var same: bool = pos_a.size() == pos_b.size()
        if same:
                for i in range(pos_a.size()):
                        if pos_a[i] != pos_b[i]:
                                same = false
        ok(same, "Z3 restore griglia (continue) -> stesse celle")

        # --- Z4 + Z5: fasi e danno sulla prima cella ---
        var cell_pos: Vector2i = zcells.cell_positions()[0]
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 0, "Z4 parte in IDLE")
        ok(zcells.force_out(cell_pos.x, cell_pos.y), "Z4 force_out helper")

        # player fittizio NELLA cella corridoio davanti alla facciata REALE
        # della cella (API cell_facing: la cella puo' avere piu' corridoi
        # adiacenti e ne sceglie uno solo).
        var facing: Vector2i = zcells.cell_facing(cell_pos.x, cell_pos.y)
        var stub := StubPlayer.new()
        stub.position = Vector2(
                        (cell_pos.x + facing.x) * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                        C.UI_HEIGHT + (cell_pos.y + facing.y) * C.TILE_SIZE + C.TILE_SIZE * 0.5)
        var stub_far := StubPlayer.new()
        stub_far.position = Vector2(960, 540)
        var expected_dmg: int = maxi(1, int(round(stub.max_energy * C.ZOMBIE_ARM_DAMAGE_PCT)))

        # EMERGE (~500ms con margine sull'arrotondamento degli step):
        # il danno parte quando la slide supera il centro del corridoio
        for i in range(int(500.0 / 16.6667)):
                stub.tick(16.6667)
                stub_far.tick(16.6667)
                zcells.update_cells(16.6667, [stub, stub_far])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 2,
                        "Z4 dopo l'EMERGE la fase e' OUT")
        var first_hits: int = stub.hits
        ok(first_hits == 1,
                        "Z5 player nella zona: 1 tocco durante l'estensione (i-frame ~1s) (%d tocchi)" % first_hits)
        ok(stub.last_dmg == expected_dmg,
                        "Z5 danno per tocco = 20%% di max_energy (%d su %d)" % [stub.last_dmg, stub.max_energy])
        ok(stub.energy == stub.max_energy - expected_dmg,
                        "Z5 energia scalata del 20%% (%d -> %d)" % [stub.max_energy, stub.energy])
        var far_hits: int = stub_far.hits
        ok(far_hits == 0, "Z5 player lontano: mai toccato (%d)" % far_hits)

        # OUT (5s): le braccia restano fuori — il player e' fuori zona in
        # questa fase del test (misuriamo solo che la fase dura 5s esatti)
        for i in range(int(3000.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub_far])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 2,
                        "Z4 dopo 3s di OUT le braccia sono ancora fuori")
        for i in range(int(1500.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub_far])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 2,
                        "Z4 dopo 4.5s di OUT le braccia sono ancora fuori")
        # finestra stretta sulla RETRACT (450ms): 600ms bastano a entrarci
        # ma non a completarla (~27 step)
        for i in range(int(600.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub_far])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 3,
                        "Z4 dopo 5s esatti di OUT -> RETRACT")

        # RETRATTIONE: senza player in zona (le braccia a meta' slide sono
        # ancora pericolose perche' il danno dura finche' slide >= 32)
        for i in range(int(900.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub_far])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 0,
                        "Z4 dopo la ritrazione la cella torna IDLE")

        # braccia ritratte: player sopra la cella per 1s intero -> zero
        # nuovi danni (la prossima estensione casuale e' a 2.7-6.8s al L7)
        var hits_before: int = stub.hits
        for i in range(int(1000.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub])
        ok(stub.hits == hits_before,
                        "Z5 braccia ritratte: player sopra la cella NON prende danni")

        # ----------------------------------------------------------------
        print("[TEST-81] ==== %s (%d check) ====" % [
                        "TEST SUPERATO" if failures.is_empty() else "TEST FALLITO", checks])
        if failures.is_empty():
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-81] FAILURE: ", f)
                get_tree().quit(1)

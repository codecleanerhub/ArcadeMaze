## test_maze81.gd — TASK 81: test runtime FANTASMI LENZUOLO + CELLE ZOMBIE.
##
## FANTASMI (MazeGhosts) — TASK 81c: respawn INFINITO a ondate:
##   F1. pool FISSO di 3 fantasmi (bianco, rosso, verde)
##   F2. MAI budget esaurito: dopo 15 min simulati al L12 gli
##       attraversamenti completati superano abbondantemente il vecchio
##       budget (12) e continuano a crescere
##   F3. rotazione colori al L1: le ondate da 1 lenzuolo sono in ordine
##       bianco -> rosso -> verde -> bianco...
##   F4. formule livello: ondata 1/2/3 lenzuoli (L1/L2-6/L7+) e delay
##       30s -> -5s per livello -> floor 5s (L1:30, L2:25, L6:5)
##   F5. al L1 mai piu' di 1 lenzuolo alla volta; il delay tra la
##       scomparsa e la prossima ondata e' esattamente 30s
##   F6. al L12 (ondate da 3): tutti e 3 insieme, mai oltre 3, prossima
##       ondata entro attraversamento (~1.8s) + 5s + margine
##   F7. CORREZIONE UTENTE (invariata): il tocco del lenzuolo toglie il
##       33% dell'energia max (arrotondato, min 1); il SALTO sopra il
##       lenzuolo NON colpisce; il danno vale solo nel tratto emerso
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
##   Z6. CORREZIONE/SPEC: il SALTO non schiva le braccia (il tocco e'
##       unblockable: si attende solo la ritrazione)
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
## damage_timer del Player reale) per contare i TOCCHI, non i frame, e il
## SALTO (is_jumping del Player reale) per la correzione utente TASK 81.
class StubPlayer:
        extends RefCounted
        var position: Vector2 = Vector2.ZERO
        var max_energy: int = 5
        var energy: int = 5
        var hits: int = 0
        var last_dmg: int = 0
        var invuln_ms: float = 0.0
        var jumping: bool = false

        func tick(delta_ms: float) -> void:
                invuln_ms = maxf(0.0, invuln_ms - delta_ms)

        func take_hazard_damage(dmg: int, unblockable: bool = false) -> void:
                if invuln_ms > 0.0:
                        return
                # mirror Player.take_hazard_damage: il salto protegge dai
                # pericoli NORMALI, non da quelli unblockable (braccia).
                if not unblockable and jumping:
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
        # FANTASMI (TASK 81c) — formule, respawn INFINITO a ondate,
        # rotazione colori, caps per livello e danni.
        # ----------------------------------------------------------------
        var maze: Node = MazeScript.new()
        add_child(maze)

        # --- F4: formule pure (ondate e delay in funzione del livello) ---
        ok(C.ghost_wave_size(1) == 1, "F4 ondata L1 = 1 lenzuolo")
        ok(C.ghost_wave_size(2) == 2, "F4 ondata L2 = 2 lenzuoli")
        ok(C.ghost_wave_size(6) == 2, "F4 ondata L6 = 2 lenzuoli")
        ok(C.ghost_wave_size(7) == 3, "F4 ondata L7 = 3 lenzuoli (tutti insieme)")
        ok(C.ghost_wave_size(50) == 3, "F4 ondata L50 = 3 (cap)")
        ok(absf(C.ghost_wave_respawn_ms(1) - 30000.0) < 0.01, "F4 delay L1 = 30s")
        ok(absf(C.ghost_wave_respawn_ms(2) - 25000.0) < 0.01, "F4 delay L2 = 25s")
        ok(absf(C.ghost_wave_respawn_ms(3) - 20000.0) < 0.01, "F4 delay L3 = 20s")
        ok(absf(C.ghost_wave_respawn_ms(5) - 10000.0) < 0.01, "F4 delay L5 = 10s")
        ok(absf(C.ghost_wave_respawn_ms(6) - 5000.0) < 0.01, "F4 delay L6 = 5s (floor)")
        ok(absf(C.ghost_wave_respawn_ms(12) - 5000.0) < 0.01, "F4 delay L12 = 5s (floor)")

        # --- F1 + F2: livello 12, respawn INFINITO (mai budget) ---
        maze.generate(12)
        var ghosts: Node = MazeGhostsScript.new()
        add_child(ghosts)
        ghosts.generate(12, maze)
        ok(ghosts.ghost_count() == 3, "F1 pool fisso di 3 fantasmi")
        var pool_colors: Array = []
        for gi in range(3):
                pool_colors.append(ghosts.ghost_state(gi)["color"])
        ok(pool_colors == ["white", "red", "green"], "F1 colori pool = bianco, rosso, verde")
        ok(ghosts.crossing_count() > 0, "F1 il labirinto offre attraversamenti (%d)" % ghosts.crossing_count())

        var max_simul_12: int = 0
        # 15 minuti di gioco simulati a step da ~16.7ms
        var steps: int = int(900000.0 / 16.6667)
        for i in range(steps):
                ghosts.update_ghosts(16.6667, [])
                max_simul_12 = maxi(max_simul_12, ghosts.active_count())
        var runs_15min: int = ghosts.total_runs()
        ok(runs_15min > 100,
                        "F2 respawn INFINITO: %d attraversamenti in 15 min (vecchio budget 12)" % runs_15min)
        ok(max_simul_12 == 3, "F6 al L12 tutti e 3 insieme (max simultanei %d)" % max_simul_12)
        # F2: e continuano per sempre — altri 40s -> altri attraversamenti
        for i in range(int(40000.0 / 16.6667)):
                ghosts.update_ghosts(16.6667, [])
        ok(ghosts.total_runs() > runs_15min,
                        "F2 dopo altri 40s gli attraversamenti crescono ancora (%d -> %d)"
                        % [runs_15min, ghosts.total_runs()])

        # --- F6: delay effettivo al L12 — quando l'ultimo lenzuolo sparisce
        # il countdown della prossima ondata parte da 5s esatti ---
        var delay_l12: float = -1.0
        var guard_cad: int = 0
        while guard_cad < int(60000.0 / 16.6667) and delay_l12 < 0.0:
                ghosts.update_ghosts(16.6667, [])
                if ghosts.active_count() == 0:
                        var wi12: Dictionary = ghosts.wave_info()
                        if not wi12["flying"] and absf(float(wi12["next_ms"]) - 5000.0) < 0.001:
                                delay_l12 = float(wi12["next_ms"])
                guard_cad += 1
        ok(delay_l12 > 0.0,
                        "F6 delay ondata successiva al L12 = 5s (visto %.1f)" % delay_l12)

        # --- F3 + F5: livello 1 — un lenzuolo alla volta in ROTAZIONE,
        # delay 30s esatti tra la scomparsa e la prossima ondata ---
        maze.generate(1)
        ghosts.generate(1, maze)
        var run_colors: Array = []
        var max_simul_1: int = 0
        var delay_l1: float = -1.0
        steps = int(200000.0 / 16.6667)  # 200s: ~5-6 ondate da 1 lenzuolo
        for i in range(steps):
                ghosts.update_ghosts(16.6667, [])
                max_simul_1 = maxi(max_simul_1, ghosts.active_count())
                if ghosts.active_count() > 0:
                        var col_now: String = ""
                        for gi in range(3):
                                if ghosts.ghost_state(gi)["active"]:
                                        col_now = ghosts.ghost_state(gi)["color"]
                                        break
                        if run_colors.is_empty() or run_colors[-1] != col_now:
                                run_colors.append(col_now)
                else:
                        var wi1: Dictionary = ghosts.wave_info()
                        if not wi1["flying"] and absf(float(wi1["next_ms"]) - 30000.0) < 0.001:
                                delay_l1 = float(wi1["next_ms"])
        ok(max_simul_1 == 1, "F5 al L1 mai piu' di 1 lenzuolo alla volta (max %d)" % max_simul_1)
        ok(delay_l1 > 0.0,
                        "F5 delay ondata successiva al L1 = 30s esatti (visto %.1f)" % delay_l1)
        ok(run_colors.size() >= 4 and run_colors.slice(0, 4) == ["white", "red", "green", "white"],
                        "F3 rotazione al L1: bianco -> rosso -> verde -> bianco (%s)" % str(run_colors))

        # ----------------------------------------------------------------
        # F7 — CORREZIONE UTENTE (invariata): il lenzuolo e' DANNOSO
        # (-33% al tocco, il salto evita). L'attraversamento e' muro A ->
        # corridoio -> muro B: il tocco vale solo nel tratto emerso
        # (EMERGE_LEN_PX dai muri), il player a meta' corridoio viene
        # colpito, quello che SALTA sopra il lenzuolo no.
        # ----------------------------------------------------------------
        maze.generate(12)
        ghosts.generate(12, maze)
        var g0: Dictionary = ghosts.force_launch(0)
        ok(bool(g0.get("active", false)), "F7 lenzuolo lanciato (force_launch)")
        var stub_g := StubPlayer.new()
        var stub_far_g := StubPlayer.new()
        var expected_g_dmg: int = maxi(1, int(round(
                        float(stub_g.max_energy) * C.GHOST_TOUCH_DAMAGE_PCT)))
        # avanza finche' il lenzuolo e' EMERSO nel corridoio (> EMERGE_LEN_PX
        # = 28px dal muro A, e' a 72px/s -> ~30 step da 16.7ms)
        var guard: int = 0
        while guard < 120 \
                        and (float(g0["travel_total"]) - float(g0["travel_left"])) < 34.0:
                ghosts.update_ghosts(16.6667, [])
                guard += 1
        ok((float(g0["travel_total"]) - float(g0["travel_left"])) >= 34.0,
                        "F7 lenzuolo emerso nel corridoio dopo %d step" % guard)
        # player ESATTAMENTE sul lenzuolo -> tocco
        stub_g.position = g0["pos"]
        ghosts.update_ghosts(16.6667, [stub_g, stub_far_g])
        ok(stub_g.hits == 1, "F7 tocco lenzuolo: 1 colpo (%d)" % stub_g.hits)
        ok(stub_g.last_dmg == expected_g_dmg,
                        "F7 danno tocco = 33%% arrotondato (%d su max %d)" % [stub_g.last_dmg, stub_g.max_energy])
        ok(stub_g.energy == stub_g.max_energy - expected_g_dmg,
                        "F7 energia scalata del 33%% (%d -> %d)" % [stub_g.max_energy, stub_g.energy])
        ok(stub_far_g.hits == 0, "F7 player lontano mai toccato (%d)" % stub_far_g.hits)
        # SALTO sopra il lenzuolo: protetto
        stub_g.invuln_ms = 0.0
        stub_g.jumping = true
        stub_g.position = g0["pos"]
        ghosts.update_ghosts(16.6667, [stub_g])
        ok(stub_g.hits == 1, "F7 SALTO sopra il lenzuolo: nessun nuovo colpo")
        # atterrato sul lenzuolo: nuovo colpo
        stub_g.jumping = false
        stub_g.invuln_ms = 0.0
        stub_g.position = g0["pos"]
        ghosts.update_ghosts(16.6667, [stub_g])
        ok(stub_g.hits == 2, "F7 atterrato sul lenzuolo: nuovo colpo (tot %d)" % stub_g.hits)

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

        # --- Z6 (spec utente): le braccia NON si schivano saltando ---
        # il tocco e' unblockable (take_hazard_damage(dmg, true)): il salto
        # protegge dai fantasmi ma MAI dalle braccia ("Il player non puo'
        # schivare le braccia ma solo attendere le vengano ritratte").
        ok(zcells.force_out(cell_pos.x, cell_pos.y), "Z6 force_out di nuovo")
        stub.jumping = true
        stub.invuln_ms = 0.0
        # avanza fino a OUT (EMERGE ~450ms) e poi ancora un tocco: anche
        # saltando, il player nella cella davanti viene colpito
        for i in range(int(500.0 / 16.6667)):
                stub.tick(16.6667)
                zcells.update_cells(16.6667, [stub])
        ok(zcells.cell_phase(cell_pos.x, cell_pos.y) == 2, "Z6 braccia di nuovo OUT")
        ok(stub.hits == hits_before + 1,
                        "Z6 SALTO non schiva le braccia: colpo comunque (%d -> %d)" % [hits_before, stub.hits])
        ok(stub.last_dmg == expected_dmg,
                        "Z6 danno braccia invariato anche saltando (%d)" % stub.last_dmg)

        # ----------------------------------------------------------------
        print("[TEST-81] ==== %s (%d check) ====" % [
                        "TEST SUPERATO" if failures.is_empty() else "TEST FALLITO", checks])
        if failures.is_empty():
                get_tree().quit(0)
        else:
                for f in failures:
                        print("[TEST-81] FAILURE: ", f)
                get_tree().quit(1)

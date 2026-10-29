## test_freeze_scroll.gd — TASK 50: test funzionale runtime (headless)
## della PERGAMENA DEL GHIACCIO.
##   A. COSTANTI: 2 colpi, 5000 punti/congelamento, gittata 9 celle, raggio
##      hit 20px, flag rollback SCROLL_FREEZE_ENABLED, enum Kind e SFX.
##   B. SCHEDULING: start_level(10) -> freeze WAIT con timer nella STESSA
##      finestra delle altre pergamene; timer forzato -> BEACON (bagliore
##      CELESTE GHIACCIO); telegrafo scaduto -> FULMINE tinto ghiaccio +
##      ONDA DI LUCE + pergamena a TERRA (lifetime 16s+2s) e contatore
##      apparizioni 1/2.
##   C. RACCOLTA = EQUIP: player sulla pergamena -> la raccoglie e la
##      EQUIPAGGIA (2 colpi, sprite in spalla, evento chiuso DONE).
##   D. RAGGIO CONGELANTE: beam lungo un corridoio dritto -> TUTTI i
##      nemici sulla traiettoria congelati (one-shot: health=0, frozen,
##      is_dead) + 5000 punti l'uno + vivi diminuiti; colpi 2->1.
##      I congelati RESTANO nel pool (remove_dead non li rimuove), non si
##      muovono (update_enemy no-op), ignorano danni ulteriori.
##   E. MID-BOSS: troppo potente per congelare — il beam gli infligge il
##      50% degli HP max, resta vivo e NON viene rimosso.
##   F. SECONDO COLPO: altri nemici congelati, colpi 1->0 -> pergamena
##      RIMOSSA dal player (equip false, freeze_scroll_player=0).
##   G. SCADENZA + RESPAWN: pergamena non raccolta svanisce -> seconda
##      apparizione programmata (WAIT, finestra 15-45s); alla terza
##      scadenza con budget 2/2 -> DONE (mai una terza apparizione).
##   H. SNAPSHOT: l'equip (player + colpi) sopravvive al salvataggio.
##   I. ROLLBACK: SCROLL_FREEZE_ENABLED=false -> nessuna programmazione.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const CollectiblesClass = preload("res://scripts/items/Collectibles.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []
var corridor_cells: Array = []
var corridor_dir: Vector2i = Vector2i(1, 0)


func _ready() -> void:
        # TASK 51: le card bonus non devono mettere in pausa i test automatici
        GameManager.mark_all_bonus_cards_seen()
        print("[TEST] boot MainGame per la pergamena del ghiaccio...")
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


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 90.0:
                _fail("timeout globale del test (90s)")
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
                                _phaseB_scheduling()
                                _next(2)
                2:
                        _phaseC_pickup_equip()
                        _next(3)
                3:
                        _phaseD_freeze_ray()
                        _next(4)
                4:
                        _phaseE_midboss()
                        _next(5)
                5:
                        _phaseF_second_shot_unequip()
                        _next(6)
                6:
                        _phaseG_expiry_respawn()
                        _next(7)
                7:
                        _phaseH_snapshot()
                        _next(8)
                8:
                        _phaseI_rollback()
                        _finish()


func _cell_center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


## Trova il corridoio piu' lungo (direzione cardinale) partendo dalla
## cella del player: ritorna le celle EMPTY consecutive (max 4) e imposta
## corridor_dir. Serve per piazzare i nemici DAVVERO sulla traiettoria.
func _find_corridor() -> Array:
        var p_grid: Vector2i = main.player.get_grid_pos()
        var best_cells: Array = []
        var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
        for d in dirs:
                var cells: Array = []
                var cc: int = p_grid.x + d.x
                var rr: int = p_grid.y + d.y
                while cells.size() < 4 \
                                and cc >= 0 and cc < C.MAZE_COLS \
                                and rr >= 0 and rr < C.MAZE_ROWS \
                                and main.maze.get_cell_type(cc, rr) == C.CellType.EMPTY:
                        cells.append(Vector2i(cc, rr))
                        cc += d.x
                        rr += d.y
                if cells.size() > best_cells.size():
                        best_cells = cells
                        corridor_dir = d
        return best_cells


## Teleporta `count` nemici vivi sulle prime `count` celle del corridoio.
## Tutti gli ALTRI nemici vivi vengono spostati in una cella LONTANA
## (> 9.5 celle dal player: fuori gittata del beam) cosi' il test e'
## deterministico anche con maze RNG non seedato (nemici casuali entro
## 20px dalla traiettoria verrebbero congelati anch'essi).
## Ritorna la lista dei nemici spostati sul corridoio.
func _place_enemies_on_corridor(count: int) -> Array:
        var placed: Array = []
        var idx: int = 0
        var far_cell: Vector2i = _far_empty_cell()
        for e in main.spawner.enemies:
                if placed.size() >= count:
                        break
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                if idx < count:
                        var cell: Vector2i = corridor_cells[idx]
                        e.position = _cell_center(cell.x, cell.y)
                        e.last_pos = e.position
                        placed.append(e)
                        idx += 1
        # gli altri vivi: lontano dalla traiettoria (fuori gittata)
        for e in main.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                if placed.has(e):
                        continue
                e.position = _cell_center(far_cell.x, far_cell.y)
                e.last_pos = e.position
        return placed


## Cellina EMPTY piu' lontana dal player (> 9.5 celle se possibile).
func _far_empty_cell() -> Vector2i:
        var p_grid: Vector2i = main.player.get_grid_pos()
        var best: Vector2i = Vector2i(1, 1)
        var best_d: float = -1.0
        for r in range(1, C.MAZE_ROWS - 1, 3):
                for c in range(1, C.MAZE_COLS - 1, 3):
                        if main.maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        if C.is_tunnel_cell(c, r):
                                continue
                        var d: float = Vector2(c - p_grid.x, r - p_grid.y).length()
                        if d > best_d:
                                best_d = d
                                best = Vector2i(c, r)
        return best


func _face_corridor_dir() -> void:
        main.player.dx = 0
        main.player.dy = 0
        main.player.last_dx = corridor_dir.x
        main.player.last_dy = corridor_dir.y


# ===========================================================================
# A — COSTANTI
# ===========================================================================
func _phaseA_constants() -> void:
        if C.SCROLL_FREEZE_CHARGES != 2:
                _fail("A: colpi %d, attesi 2" % C.SCROLL_FREEZE_CHARGES)
        elif C.SCROLL_FREEZE_POINTS != 5000:
                _fail("A: punti %d, attesi 5000" % C.SCROLL_FREEZE_POINTS)
        elif C.SCROLL_FREEZE_RANGE_CELLS != 9:
                _fail("A: gittata %d, attesa 9 celle" % C.SCROLL_FREEZE_RANGE_CELLS)
        elif absf(C.SCROLL_FREEZE_HIT_RADIUS_PX - 20.0) > 0.01:
                _fail("A: raggio hit %.0f, atteso 20" % C.SCROLL_FREEZE_HIT_RADIUS_PX)
        elif absf(C.SCROLL_FREEZE_MINIBOSS_DMG_PCT - 0.5) > 0.001:
                _fail("A: danno miniboss %.2f, atteso 0.50"
                                % C.SCROLL_FREEZE_MINIBOSS_DMG_PCT)
        elif CollectiblesClass.Kind.FREEZE_SCROLL <= CollectiblesClass.Kind.CHASM_SCROLL:
                _fail("A: enum Kind.FREEZE_SCROLL non aggiunto in coda")
        else:
                _ok("A: costanti (2 colpi, 5000 punti, gittata 9 celle, hit 20px)")
        # flag rollback presente e scrivibile
        C.SCROLL_FREEZE_ENABLED = false
        C.SCROLL_FREEZE_ENABLED = true
        _ok("A: flag rollback SCROLL_FREEZE_ENABLED presente")


# ===========================================================================
# B — SCHEDULING + TELEGRAFO + SPAWN (stesse tempistiche delle altre)
# ===========================================================================
func _phaseB_scheduling() -> void:
        main.is_paused = true
        main.start_level(10)
        if main.scroll_freeze_phase != main.ScrollPhase.WAIT:
                _fail("B: fase iniziale %d, attesa WAIT" % main.scroll_freeze_phase)
        elif main.scroll_freeze_timer_ms < float(C.PARCHMENT_FIRST_MIN_MS) \
                        or main.scroll_freeze_timer_ms > float(C.PARCHMENT_FIRST_MAX_MS):
                _fail("B: timer fuori finestra (%.0f)"
                                % main.scroll_freeze_timer_ms)
        else:
                _ok("B: pergamena ghiaccio programmata (timer %.0fs, finestra 25-70s come le altre)"
                                % (main.scroll_freeze_timer_ms / 1000.0))
        # timer forzato -> BEACON
        main.scroll_freeze_timer_ms = 1.0
        main._update_parchments(16.0)
        if main.scroll_freeze_phase != main.ScrollPhase.BEACON:
                _fail("B: timer scaduto non accende il telegrafo (fase %d)"
                                % main.scroll_freeze_phase)
        elif main.scroll_freeze_beacon == null \
                        or not is_instance_valid(main.scroll_freeze_beacon):
                _fail("B: beacon mancante")
        elif absf(main.scroll_freeze_beacon.modulate.r - 0.35) \
                        + absf(main.scroll_freeze_beacon.modulate.g - 0.8) \
                        + absf(main.scroll_freeze_beacon.modulate.b - 1.0) > 0.05:
                _fail("B: beacon colore %s, atteso celeste ghiaccio"
                                % str(main.scroll_freeze_beacon.modulate))
        else:
                _ok("B: telegrafo = bagliore CELESTE GHIACCIO sulla cella")
        # telegrafo scaduto -> pergamena a terra + fulmine + onda
        main.scroll_freeze_timer_ms = 1.0
        main._update_parchments(16.0)
        var has_strike: bool = false
        var has_wave: bool = false
        for n in main.collectibles_node.get_children():
                if n.get_script() == main.LightningStrikeFx:
                        has_strike = true
                elif n.get_script() == main.MazeLightWaveFx:
                        has_wave = true
        if main.scroll_freeze_phase != main.ScrollPhase.GROUND:
                _fail("B: telegrafo scaduto non fa apparire la pergamena (%d)"
                                % main.scroll_freeze_phase)
        elif main.scroll_freeze_item == null \
                        or not is_instance_valid(main.scroll_freeze_item):
                _fail("B: pergamena ghiaccio non a terra")
        elif main.scroll_freeze_item.kind != CollectiblesClass.Kind.FREEZE_SCROLL:
                _fail("B: kind %d, atteso FREEZE_SCROLL"
                                % main.scroll_freeze_item.kind)
        elif absf(main.scroll_freeze_item.scroll_lifetime_ms
                        - float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)) > 1.0:
                _fail("B: lifetime %.0f, atteso %.0f (16s+2s come le altre)"
                                % [main.scroll_freeze_item.scroll_lifetime_ms,
                                        float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)])
        elif main.scroll_freeze_spawns_used != 1:
                _fail("B: apparizioni %d, attesa 1" % main.scroll_freeze_spawns_used)
        elif not has_strike:
                _fail("B: fulmine tinto ghiaccio mancante")
        elif not has_wave:
                _fail("B: onda di luce mancante")
        else:
                _ok("B: fulmine + onda + pergamena a terra (1/2 apparizioni, "
                                + "vita 18s)")


# ===========================================================================
# C — RACCOLTA = EQUIPAGGIAMENTO
# ===========================================================================
func _phaseC_pickup_equip() -> void:
        # player NON sul posto di partenza ma teleportato sulla pergamena
        main.player.position = main.scroll_freeze_item.position
        main._update_collectibles(16.0)
        if main.freeze_scroll_player != 1:
                _fail("C: player equip %d, atteso 1" % main.freeze_scroll_player)
        elif main.freeze_charges_left != C.SCROLL_FREEZE_CHARGES:
                _fail("C: colpi %d, attesi %d"
                                % [main.freeze_charges_left, C.SCROLL_FREEZE_CHARGES])
        elif not main.player.is_freeze_scroll_equipped():
                _fail("C: pergamena non equipaggiata (sprite in spalla mancante)")
        elif main.scroll_freeze_phase != main.ScrollPhase.DONE:
                _fail("C: evento non chiuso alla raccolta (fase %d)"
                                % main.scroll_freeze_phase)
        elif main.scroll_freeze_item != null:
                _fail("C: item a terra non liberato")
        else:
                _ok("C: raccolta = equipaggiamento (2 colpi, evento chiuso)")


# ===========================================================================
# D — RAGGIO CONGELANTE (one-shot, sprite congelato resta sul labirinto)
# ===========================================================================
func _phaseD_freeze_ray() -> void:
        corridor_cells = _find_corridor()
        if corridor_cells.size() < 2:
                _fail("D: corridoio troppo corto per il test (%d celle)"
                                % corridor_cells.size())
                return
        var targets: Array = _place_enemies_on_corridor(2)
        if targets.size() < 2:
                _fail("D: nemici vivi insufficienti (%d)" % targets.size())
                return
        _face_corridor_dir()
        var alive_before: int = main.spawner.alive_count()
        var score_before: int = main.player.score
        var pos_before: Array = [targets[0].position, targets[1].position]
        main._fire_freeze_ray(main.player)

        if main.freeze_charges_left != 1:
                _fail("D: colpi rimasti %d, atteso 1" % main.freeze_charges_left)
        elif not targets[0].is_frozen() or not targets[1].is_frozen():
                _fail("D: nemici sulla traiettoria non congelati")
        elif not targets[0].is_dead() or not targets[1].is_dead():
                _fail("D: congelati non contano come uccisi (health %d/%d)"
                                % [targets[0].health, targets[1].health])
        elif targets[0].is_death_anim_done() or targets[1].is_death_anim_done():
                _fail("D: congelati marcati death-anim-done (verrebbero rimossi)")
        elif main.spawner.alive_count() != alive_before - 2:
                _fail("D: vivi %d, attesi %d"
                                % [main.spawner.alive_count(), alive_before - 2])
        elif main.player.score < score_before + 2 * C.SCROLL_FREEZE_POINTS:
                _fail("D: punti +%d, attesi +%d"
                                % [main.player.score - score_before,
                                        2 * C.SCROLL_FREEZE_POINTS])
        else:
                _ok("D: raggio = one-shot multipli (+%d punti, colpi 2->1)"
                                % (main.player.score - score_before))

        # congelato = statua: update_enemy no-op + danni ignorati + resta nel pool
        for i in 30:
                targets[0].update_enemy(main.maze, Vector2i.ZERO,
                                Vector2.ZERO, [], 16.0)
        targets[0].take_damage(99999)
        var still_in_pool_0: bool = main.spawner.enemies.has(targets[0])
        main.spawner.remove_dead()
        var still_in_pool: bool = main.spawner.enemies.has(targets[0]) \
                        and main.spawner.enemies.has(targets[1])
        if targets[0].position != pos_before[0]:
                _fail("D: congelato si e' mosso (%s -> %s)"
                                % [str(pos_before[0]), str(targets[0].position)])
        elif not still_in_pool_0:
                _fail("D: congelato rimosso PRIMA di remove_dead")
        elif not still_in_pool:
                _fail("D: remove_dead ha rimosso i congelati dal labirinto")
        elif not targets[0].is_frozen():
                _fail("D: take_damage ha sbloccato il congelamento")
        else:
                _ok("D: congelati = statue ferme per tutto il livello (no AI, no danni, mai rimossi)")
        # beam visuale in scena
        var has_beam: bool = false
        for n in main.collectibles_node.get_children():
                if n.get_script() == main.IceBeamFx:
                        has_beam = true
                        break
        if not has_beam:
                _fail("D: effetto visuale IceBeamEffect mancante")
        else:
                _ok("D: raggio congelante visibile in scena")


# ===========================================================================
# E — MID-BOSS: non congelabile, subisce il 50% degli HP max
# ===========================================================================
func _phaseE_midboss() -> void:
        # ri-equip manuale per il test del mid-boss (1 colpo)
        main.freeze_scroll_player = 1
        main.freeze_charges_left = 1
        main.player.set_freeze_scroll_equipped(true)
        # spawn di un mid-boss sull'ULTIMA cella del corridoio (sicuramente
        # sulla traiettoria del beam, a prescindere dalla lunghezza)
        if corridor_cells.size() < 2:
                _ok("E: corridoio corto, mid-boss test saltato (coperto da SCROLL_FREEZE_MINIBOSS_DMG_PCT)")
                return
        if main.mini_boss != null and is_instance_valid(main.mini_boss):
                main.mini_boss.queue_free()
        main.mini_boss = null
        main.mini_boss_spawned = false
        var mb_cell: Vector2i = corridor_cells[corridor_cells.size() - 1]
        main._spawn_mini_boss(mb_cell.x, mb_cell.y)
        if main.mini_boss == null or not is_instance_valid(main.mini_boss):
                _fail("E: mid-boss non spawnato")
                return
        var mb_max: int = main.mini_boss.get_max_health()
        var mb_hp_before: int = main.mini_boss.health
        _face_corridor_dir()
        main._fire_freeze_ray(main.player)
        var mb_hp_after: int = main.mini_boss.health
        if is_instance_valid(main.mini_boss) and main.mini_boss.is_dead():
                _fail("E: mid-boss ucciso dal raggio (doveva solo danneggiato)")
        elif absi(mb_hp_before - mb_hp_after - int(round(float(mb_max) * 0.5))) > 1:
                _fail("E: danno mid-boss %d, atteso ~%d (50%% di %d)"
                                % [mb_hp_before - mb_hp_after,
                                        int(round(float(mb_max) * 0.5)), mb_max])
        else:
                _ok("E: mid-boss non congelabile — subisce il 50%% degli HP "
                                + "(%d/%d) e resta in campo" % [mb_hp_after, mb_max])


# ===========================================================================
# F — SECONDO COLPO + RIMOZIONE PERGAMENA
# ===========================================================================
func _phaseF_second_shot_unequip() -> void:
        # (il colpo del mid-boss in fase E ha gia' consumato l'ultimo colpo)
        if main.freeze_charges_left != 0:
                _fail("F: colpi %d, atteso 0 dopo il colpo del mid-boss"
                                % main.freeze_charges_left)
        elif main.freeze_scroll_player != 0:
                _fail("F: pergamena non rimossa a colpi esauriti (player %d)"
                                % main.freeze_scroll_player)
        elif main.player.is_freeze_scroll_equipped():
                _fail("F: sprite pergamena ancora in spalla a colpi esauriti")
        else:
                _ok("F: secondo colpo consumato -> pergamena rimossa dal player")


# ===========================================================================
# G — SCADENZA + RESPAWN (2 apparizioni per livello, mai 3)
# ===========================================================================
func _phaseG_expiry_respawn() -> void:
        # simula una pergamena a terra non raccolta con budget residuo
        main._free_scroll_visuals()
        main.scroll_freeze_spawns_used = 1
        main.scroll_freeze_phase = main.ScrollPhase.WAIT
        main.scroll_freeze_timer_ms = 1.0
        main._update_parchments(16.0)   # -> BEACON
        main.scroll_freeze_timer_ms = 1.0
        main._update_parchments(16.0)   # -> GROUND (2/2)
        if main.scroll_freeze_phase != main.ScrollPhase.GROUND \
                        or main.scroll_freeze_item == null:
                _fail("G: seconda apparizione non avvenuta (fase %d)"
                                % main.scroll_freeze_phase)
                return
        # scadenza a terra: svanisce e con budget 2/2 -> DONE
        main.scroll_freeze_item.active = false
        main._update_parchments(16.0)
        if main.scroll_freeze_phase != main.ScrollPhase.WAIT \
                        and main.scroll_freeze_phase != main.ScrollPhase.DONE:
                _fail("G: fase post-scadenza %d, attesa WAIT o DONE"
                                % main.scroll_freeze_phase)
        elif main.scroll_freeze_phase == main.ScrollPhase.WAIT:
                # budget residuo (spawns_used < 2 non dovrebbe piu' valere:
                # spawns_used e' 2) — questo ramo non deve succedere
                _fail("G: respawn programmato nonostante budget 2/2 esaurito")
        elif main.scroll_freeze_phase != main.ScrollPhase.DONE:
                _fail("G: evento non chiuso (fase %d)" % main.scroll_freeze_phase)
        else:
                _ok("G: scaduta 2 volte -> DONE (mai una terza apparizione)")
        # caso budget residuo: 1 sola apparizione usata -> respawn in WAIT
        main._free_scroll_visuals()
        main.scroll_freeze_spawns_used = 1
        main.scroll_freeze_phase = main.ScrollPhase.GROUND
        main.scroll_freeze_item = null
        # il watcher GROUND con item nullo chiama consume(false) -> WAIT
        main._update_parchments(16.0)
        if main.scroll_freeze_phase != main.ScrollPhase.WAIT:
                _fail("G: svanita con budget residuo non riprogrammata (%d)"
                                % main.scroll_freeze_phase)
        elif main.scroll_freeze_timer_ms < float(C.PARCHMENT_NEXT_MIN_MS) \
                        or main.scroll_freeze_timer_ms > float(C.PARCHMENT_NEXT_MAX_MS):
                _fail("G: timer 2a apparizione %.0f fuori finestra 15-45s"
                                % main.scroll_freeze_timer_ms)
        else:
                _ok("G: svanita non raccolta -> respawn programmato "
                                + "(%.0fs, finestra 15-45s)"
                                % (main.scroll_freeze_timer_ms / 1000.0))


# ===========================================================================
# H — SNAPSHOT dell'equip
# ===========================================================================
func _phaseH_snapshot() -> void:
        main.freeze_scroll_player = 1
        main.freeze_charges_left = 2
        var snap: Dictionary = main._build_session_snapshot()
        if not snap.has("freeze_scroll"):
                _fail("H: snapshot senza stato pergamena ghiaccio")
        elif int(snap["freeze_scroll"]["player"]) != 1 \
                        or int(snap["freeze_scroll"]["charges_left"]) != 2:
                _fail("H: snapshot freeze_scroll errato: %s"
                                % str(snap.get("freeze_scroll")))
        else:
                _ok("H: snapshot preserva l'equip (player 1, 2 colpi)")


# ===========================================================================
# I — ROLLBACK
# ===========================================================================
func _phaseI_rollback() -> void:
        C.SCROLL_FREEZE_ENABLED = false
        main._reset_parchments(10)
        if main.scroll_freeze_phase != main.ScrollPhase.DONE:
                _fail("I: rollback non rispettato (fase %d)"
                                % main.scroll_freeze_phase)
        elif main.scroll_quake_phase != main.ScrollPhase.WAIT:
                _fail("I: rollback ghiaccio ha spento anche le altre pergamene")
        else:
                _ok("I: rollback SCROLL_FREEZE_ENABLED=false -> solo ghiaccio OFF")
        C.SCROLL_FREEZE_ENABLED = true
        main._reset_parchments(10)
        if main.scroll_freeze_phase != main.ScrollPhase.WAIT:
                _fail("I: riabilitazione non funzionante (fase %d)"
                                % main.scroll_freeze_phase)
        else:
                _ok("I: riabilitazione -> pergamena ghiaccio riprogrammata")


func _finish() -> void:
        print("")
        print("========================================")
        if failures.is_empty():
                print("[TEST] TUTTI I CHECK DELLA PERGAMENA GHIACCIO PASSATI")
                print("========================================")
                get_tree().quit(0)
        else:
                print("[TEST] %d CHECK FALLITI:" % failures.size())
                for f in failures:
                        print("  - ", f)
                print("========================================")
                get_tree().quit(1)

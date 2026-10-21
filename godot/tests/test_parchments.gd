## test_parchments.gd — Test funzionale runtime (headless) delle due
## PERGAMENE EVENTO del Task 35 + modifiche TASK 36 + TASK 38:
##   A. COSTANTI: finestra di apparizione, timing vita/blink, rollback
##      PARCHMENTS_ENABLED, grace level 5; TASK 36: soglia vivi 30%,
##      max 2 apparizioni con 1 solo uso, finestra 2a apparizione.
##   B. SCHEDULING: start_level(10) -> entrambe WAIT con timer in finestra;
##      timer forzato + vivi >= 30% -> BEACON (bagliore sulla cella);
##      telegrafo scaduto -> FULMINE + pergamena a TERRA (lifetime 16s+2s,
##      +50% TASK 41)
##      e contatore apparizioni incrementato. TASK 38: allo spawn nasce
##      anche l'ONDA DI LUCE additiva con raggio fino all'angolo piu'
##      lontano del labirinto (copre TUTTA la sua dimensione).
##   C. CONDIZIONE 30% (TASK 36): con i vivi TRA il 30% e il 50% lo spawn
##      ORA e' CONSENTITO (prima no); con i vivi SOTTO il 30% il timer
##      scaduto NON spawna nulla e riprova dopo PARCHMENT_RETRY_MS.
##   D. TERREMOTO: raccolta = -50% HP max a tutti i nemici; nemico gia'
##      ferito (sotto soglia dopo il colpo) ELIMINATO +5000 punti; il
##      player NON subisce danni (energia invariata). L'USO chiude
##      l'evento (DONE: nessuna seconda apparizione).
##   E. VORAGINI: raccolta -> 4 voragini BEN DISTANZIATE (Manhattan >= 5);
##      nemico sulla cella UCCISO (+5000); player sulla cella ILLESO;
##      fine ondata (4s + fade) -> RIPOSIZIONAMENTO in nuove 4 celle,
##      per 3 ondate totali; alla fine tutto pulito.
##   F. SCADENZA: pergamena non raccolta: 10s + 2s di blink -> active=false
##      e il controller libera il nodo. TASK 36: scaduta NON usata con
##      budget residuo -> SECONDA apparizione programmata (WAIT, finestra
##      15-45s); con budget esaurito (2/2) -> DONE.
##   G. (TASK 36) SECONDA APPARIZIONE: il ciclo reale WAIT -> BEACON ->
##      GROUND porta il contatore a 2/2; la scadenza della seconda chiude
##      DONE (MAI una terza); la guardia budget in WAIT chiude subito.
##   H. ROLLBACK: PARCHMENTS_ENABLED=false -> nessuna programmazione.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var failures: Array = []


func _ready() -> void:
        print("[TEST] boot MainGame per le pergamene evento...")
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
                        _phaseC_alive_condition()
                        _next(3)
                3:
                        _phaseD_quake_scroll()
                        _next(4)
                4:
                        _phaseE_chasm_scroll()
                        _next(5)
                5:
                        _phaseF_expiry()
                        _next(6)
                6:
                        _phaseG_second_spawn()
                        _next(7)
                7:
                        _phaseH_rollback()
                        _finish()


func _center(c: int, r: int) -> Vector2:
        return Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)


## Un nemico vivo qualsiasi (o null).
func _any_alive_enemy():
        for e in main.spawner.enemies:
                if e != null and is_instance_valid(e) and not e.is_dead():
                        return e
        return null


# ===========================================================================
# A — COSTANTI
# ===========================================================================
func _phaseA_constants() -> void:
        if C.PARCHMENT_FIRST_MIN_MS != 25000 or C.PARCHMENT_FIRST_MAX_MS != 70000:
                _fail("A: finestra apparizione %d..%d, attesa 25000..70000"
                                % [C.PARCHMENT_FIRST_MIN_MS, C.PARCHMENT_FIRST_MAX_MS])
        elif C.PARCHMENT_VISIBLE_MS != 16000 or C.PARCHMENT_BLINK_MS != 2000:
                _fail("A: vita a terra %d+%d, attesa 16000+2000 (+50%% TASK 41)"
                                % [C.PARCHMENT_VISIBLE_MS, C.PARCHMENT_BLINK_MS])
        elif C.SCROLL_CHASM_COUNT != 4 or C.SCROLL_CHASM_WAVE_MS != 4000 \
                        or C.SCROLL_CHASM_WAVES != 3:
                _fail("A: costanti voragini errate (%d/%d/%d)"
                                % [C.SCROLL_CHASM_COUNT, C.SCROLL_CHASM_WAVE_MS,
                                        C.SCROLL_CHASM_WAVES])
        elif C.SCROLL_QUAKE_DAMAGE_PCT != 0.5 or C.SCROLL_QUAKE_KILL_PCT != 0.5:
                _fail("A: costanti terremoto errate")
        elif absf(C.PARCHMENT_MIN_ALIVE_PCT - 0.3) > 0.0001:
                _fail("A: soglia vivi %.2f, attesa 0.30"
                                % C.PARCHMENT_MIN_ALIVE_PCT)
        elif C.PARCHMENT_MAX_SPAWNS != 2:
                _fail("A: max apparizioni %d, attese 2" % C.PARCHMENT_MAX_SPAWNS)
        elif C.PARCHMENT_NEXT_MIN_MS != 15000 or C.PARCHMENT_NEXT_MAX_MS != 45000:
                _fail("A: finestra 2a apparizione %d..%d, attesa 15000..45000"
                                % [C.PARCHMENT_NEXT_MIN_MS, C.PARCHMENT_NEXT_MAX_MS])
        else:
                _ok("A: costanti (25-70s, vita 10+2s, soglia 30%, max 2, 2a 15-45s)")
        C.PARCHMENTS_ENABLED = false
        C.PARCHMENTS_ENABLED = true
        _ok("A: flag rollback PARCHMENTS_ENABLED presente")


# ===========================================================================
# B — SCHEDULING + TELEGRAFO + SPAWN
# ===========================================================================
func _phaseB_scheduling() -> void:
        main.is_paused = true
        main.start_level(10)
        var in_window: bool = true
        for t_ms in [main.scroll_quake_timer_ms, main.scroll_chasm_timer_ms]:
                if t_ms < float(C.PARCHMENT_FIRST_MIN_MS) \
                                or t_ms > float(C.PARCHMENT_FIRST_MAX_MS):
                        in_window = false
        if main.scroll_quake_phase != main.ScrollPhase.WAIT \
                        or main.scroll_chasm_phase != main.ScrollPhase.WAIT:
                _fail("B: fasi iniziali %d/%d, attese WAIT/WAIT"
                                % [main.scroll_quake_phase, main.scroll_chasm_phase])
        elif not in_window:
                _fail("B: timer fuori finestra (%.0f / %.0f)"
                                % [main.scroll_quake_timer_ms, main.scroll_chasm_timer_ms])
        else:
                _ok("B: entrambe le pergamene programmate (timer %.0fs / %.0fs)"
                                % [main.scroll_quake_timer_ms / 1000.0,
                                        main.scroll_chasm_timer_ms / 1000.0])
        # timer forzato -> BEACON (bagliore prima dell'apparizione)
        main.scroll_quake_timer_ms = 1.0
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.BEACON:
                _fail("B: timer scaduto non accende il telegrafo (fase %d)"
                                % main.scroll_quake_phase)
        elif main.scroll_quake_beacon == null \
                        or not is_instance_valid(main.scroll_quake_beacon):
                _fail("B: beacon luminoso mancante")
        else:
                _ok("B: telegrafo = bagliore/aura sulla cella prima di apparire")
        # telegrafo scaduto -> pergamena a terra
        main.scroll_quake_timer_ms = 1.0
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.GROUND:
                _fail("B: telegrafo scaduto non fa apparire la pergamena (%d)"
                                % main.scroll_quake_phase)
        elif main.scroll_quake_item == null \
                        or not is_instance_valid(main.scroll_quake_item):
                _fail("B: pergamena terremoto non a terra")
        elif absf(main.scroll_quake_item.scroll_lifetime_ms
                        - float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)) > 1.0:
                _fail("B: lifetime pergamena %.0f, atteso %.0f"
                                % [main.scroll_quake_item.scroll_lifetime_ms,
                                        float(C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)])
        elif main.scroll_quake_beacon != null:
                _fail("B: beacon non spento all'apparizione")
        else:
                _ok("B: pergamena a terra (lifetime %.0fs)"
                                % (main.scroll_quake_item.scroll_lifetime_ms / 1000.0))
        # TASK 36: spawn REALE -> contatore apparizioni + FULMINE in scena
        var has_strike: bool = false
        for n in main.collectibles_node.get_children():
                if n.get_script() == main.LightningStrikeFx:
                        has_strike = true
                        break
        if main.scroll_quake_spawns_used != 1:
                _fail("B: contatore apparizioni %d, atteso 1"
                                % main.scroll_quake_spawns_used)
        elif not has_strike:
                _fail("B: fulmine che si abbatte al suolo mancante")
        else:
                _ok("B: apparizione eclatante (FULMINE al suolo, 1/2 apparizioni)")
        # TASK 38: ONDA DI LUCE che si diffonde per TUTTO il labirinto
        # (nodo presente + materiale ADDITIVO + raggio che raggiunge
        # l'angolo piu' lontano del labirinto dal punto d'impatto).
        var has_wave: bool = false
        var wave_additive: bool = false
        var wave_r: float = 0.0
        for n in main.collectibles_node.get_children():
                if n.get_script() == main.MazeLightWaveFx:
                        has_wave = true
                        wave_r = float(n.get("_max_radius"))
                        var wmat = n.get("material")
                        wave_additive = wmat is CanvasItemMaterial \
                                        and wmat.blend_mode \
                                        == CanvasItemMaterial.BLEND_MODE_ADD
                        break
        var maze_origin: Vector2 = Vector2(0.0, float(C.UI_HEIGHT))
        var expect_r: float = 0.0
        for corner in [
                        maze_origin,
                        maze_origin + Vector2(
                                        float(C.MAZE_COLS * C.TILE_SIZE), 0.0),
                        maze_origin + Vector2(
                                        0.0, float(C.MAZE_ROWS * C.TILE_SIZE)),
                        maze_origin + Vector2(
                                        float(C.MAZE_COLS * C.TILE_SIZE),
                                        float(C.MAZE_ROWS * C.TILE_SIZE)),
                ]:
                expect_r = maxf(expect_r,
                                main.scroll_quake_item.position.distance_to(corner))
        if not has_wave:
                _fail("B: onda di luce del labirinto mancante")
        elif not wave_additive:
                _fail("B: onda di luce senza materiale additivo")
        elif wave_r < expect_r:
                _fail("B: raggio onda %.0f < distanza angolo piu' lontano %.0f"
                                % [wave_r, expect_r])
        else:
                _ok("B: ondata di luce dal fulmine su tutto il labirinto "
                                + "(raggio %.0f px, additiva)" % wave_r)
        # anche la pergamena voragini: portala a terra per i test successivi
        main.scroll_chasm_timer_ms = 1.0
        main._update_parchments(16.0)
        main.scroll_chasm_timer_ms = 1.0
        main._update_parchments(16.0)
        if main.scroll_chasm_phase != main.ScrollPhase.GROUND \
                        or main.scroll_chasm_item == null:
                _fail("B: pergamena voragini non apparsa (fase %d)"
                                % main.scroll_chasm_phase)


# ===========================================================================
# C — CONDIZIONE (TASK 36): spawn consentito dal 30% in su, negato sotto
# ===========================================================================
func _phaseC_alive_condition() -> void:
        # svuota le pergamene correnti (reset pulito senza re-scheduling)
        main._free_scroll_visuals()
        main.scroll_quake_phase = main.ScrollPhase.WAIT
        main.scroll_chasm_phase = main.ScrollPhase.DONE
        main.scroll_quake_timer_ms = 1.0
        # C1 — ammazza finche' i vivi sono TRA il 30% e il 50%: TASK 36
        # ora lo spawn e' CONSENTITO (prima, con soglia 50%, era negato)
        var total: int = maxi(1, main.spawner.initial_count)
        for e in main.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                if main.spawner.alive_count() * 10 < total * 5:
                        break
                e.take_damage(99999)
        var alive: int = main.spawner.alive_count()
        if alive * 10 >= total * 5 or alive * 10 < total * 3:
                _fail("C: preparazione C1 fallita (vivi %d su %d)"
                                % [alive, total])
        else:
                main._update_parchments(16.0)
                if main.scroll_quake_phase != main.ScrollPhase.BEACON:
                        _fail("C: vivi al %.0f%% (tra 30%% e 50%%) ma spawn negato (fase %d)"
                                        % [100.0 * alive / total,
                                                main.scroll_quake_phase])
                else:
                        _ok("C: vivi al %.0f%% (>= 30%%, < 50%%) -> spawn CONSENTITO"
                                        % [100.0 * alive / total])
        # C2 — vivi SOTTO il 30%: niente spawn, retry dopo 5s
        main._free_scroll_visuals()
        main.scroll_quake_phase = main.ScrollPhase.WAIT
        main.scroll_quake_timer_ms = 1.0
        for e in main.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                if main.spawner.alive_count() * 10 < total * 3:
                        break
                e.take_damage(99999)
        alive = main.spawner.alive_count()
        if alive * 10 >= total * 3:
                _fail("C: preparazione C2 fallita (vivi %d su %d)" % [alive, total])
                return
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.WAIT:
                _fail("C: spawn con vivi sotto il 30%% (fase %d)"
                                % main.scroll_quake_phase)
        elif absf(main.scroll_quake_timer_ms - float(C.PARCHMENT_RETRY_MS)) > 40.0:
                _fail("C: retry non programmato (%.0f, atteso %.0f)"
                                % [main.scroll_quake_timer_ms,
                                        float(C.PARCHMENT_RETRY_MS)])
        else:
                _ok("C: vivi %d/%d (< 30%%) -> niente spawn, retry tra %.0fs"
                                % [alive, total, main.scroll_quake_timer_ms / 1000.0])


# ===========================================================================
# D — PERGAMENA DEL TERREMOTO
# ===========================================================================
func _phaseD_quake_scroll() -> void:
        # rigenera nemici freschi (il livello e' stato svuotato in C)
        main.start_level(10)
        var p: CharacterBody2D = main.player
        p.energy = p.max_energy
        # crea la pergamena terremoto direttamente a terra vicino al player
        main.scroll_quake_phase = main.ScrollPhase.GROUND
        var cell_ok: Vector2i = main._random_empty_cell()
        if cell_ok == Vector2i(-1, -1):
                _fail("D: nessuna cella libera per la pergamena")
                return
        main.scroll_quake_item = main._create_collectible(
                        main.CollectiblesClass.Kind.QUAKE_SCROLL,
                        main._cell_to_pixel(cell_ok))
        main.scroll_quake_item.scroll_lifetime_ms = 12000.0
        main.collectibles_node.add_child(main.scroll_quake_item)
        # snapshot nemici: uno PIENO con HP pari (il 50% esatto esiste solo
        # con HP pari: con HP dispari anche un pieno finisce sotto soglia per
        # l'arrotondamento), uno pre-ferito
        var full = null
        var hurt = null
        for e in main.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                if full == null and e.max_health % 2 == 0:
                        full = e
                elif hurt == null:
                        hurt = e
                        hurt.health = maxi(1, hurt.max_health - 1)
        if full == null:
                _fail("D: nessun nemico vivo per il test")
                return
        var full_hp: int = full.max_health
        var score_before: int = p.score
        var e_before: int = p.energy
        main._on_collectible_picked_up(main.scroll_quake_item, p, 1)
        var expect_dmg: int = maxi(1, int(round(float(full_hp) * C.SCROLL_QUAKE_DAMAGE_PCT)))
        if main.scroll_quake_phase != main.ScrollPhase.DONE:
                _fail("D: raccolta non chiude l'evento (fase %d)" % main.scroll_quake_phase)
        elif not full.is_dead() and full.health != full_hp - expect_dmg:
                _fail("D: nemico pieno %d HP, attesi %d (max %d - %d)"
                                % [full.health, full_hp - expect_dmg, full_hp, expect_dmg])
        elif hurt != null and not hurt.is_dead():
                _fail("D: nemico ferito non eliminato dal terremoto (%d HP)"
                                % hurt.health)
        elif p.energy != e_before:
                _fail("D: il player ha subito danni (%d -> %d)" % [e_before, p.energy])
        elif hurt != null and hurt.is_dead() \
                        and p.score < score_before + C.SCROLL_QUAKE_KILL_POINTS:
                _fail("D: punti kill mancanti (%d)" % (p.score - score_before))
        else:
                var kills: int = 0
                for e in main.spawner.enemies:
                        if e != null and is_instance_valid(e) and e.is_dead():
                                kills += 1
                _ok("D: terremoto = -%d HP ai pieni, %d eliminati, player illeso (+%d punti)"
                                % [expect_dmg, kills, p.score - score_before])


# ===========================================================================
# E — PERGAMENA DELLE VORAGINI
# ===========================================================================
func _phaseE_chasm_scroll() -> void:
        var p: CharacterBody2D = main.player
        p.energy = p.max_energy
        main.scroll_chasm_phase = main.ScrollPhase.GROUND
        var cell_ok: Vector2i = main._random_empty_cell()
        main.scroll_chasm_item = main._create_collectible(
                        main.CollectiblesClass.Kind.CHASM_SCROLL,
                        main._cell_to_pixel(cell_ok))
        main.scroll_chasm_item.scroll_lifetime_ms = 12000.0
        main.collectibles_node.add_child(main.scroll_chasm_item)
        main._on_collectible_picked_up(main.scroll_chasm_item, p, 1)
        var hz = main.hazards
        if hz.scroll_chasm_list.size() != C.SCROLL_CHASM_COUNT:
                _fail("E: ondata iniziale = %d voragini, attese %d"
                                % [hz.scroll_chasm_list.size(), C.SCROLL_CHASM_COUNT])
                return
        # ben distanziate tra loro (Manhattan >= 5 su ogni coppia)
        var cells: Array[Vector2i] = hz.scroll_chasm_cells()
        for i in cells.size():
                for j in range(i + 1, cells.size()):
                        if absi(cells[i].x - cells[j].x) + absi(cells[i].y - cells[j].y) \
                                        < C.SCROLL_CHASM_MIN_GAP:
                                _fail("E: voragini %s e %s troppo vicine (gap < %d)"
                                                % [str(cells[i]), str(cells[j]),
                                                        C.SCROLL_CHASM_MIN_GAP])
                                return
        _ok("E: 4 voragini ben distanziate (gap >= %d celle)" % C.SCROLL_CHASM_MIN_GAP)
        # nemico sulla cella -> ucciso; player su un'altra -> illeso
        var victim = _any_alive_enemy()
        var score_before: int = p.score
        if victim == null:
                _fail("E: nessun nemico vivo da sacrificare")
                return
        victim.position = _center(cells[0].x, cells[0].y)
        p.set_position_abs(_center(cells[1].x, cells[1].y).x,
                        _center(cells[1].x, cells[1].y).y)
        p.energy = p.max_energy
        var e_before: int = p.energy
        var lives_before: int = p.lives
        hz.update_hazards(16.0, main.maze)
        if not victim.is_dead():
                _fail("E: nemico sulla voragine non ucciso (%d HP)" % victim.health)
        elif p.score != score_before + C.SCROLL_CHASM_KILL_POINTS:
                _fail("E: punti kill voragine %d, attesi %d"
                                % [p.score - score_before, C.SCROLL_CHASM_KILL_POINTS])
        elif p.energy != e_before or p.lives != lives_before:
                _fail("E: il player ha subito qualcosa sulla voragine")
        else:
                _ok("E: nemico caduto = ucciso (+%d punti), player immune"
                                % C.SCROLL_CHASM_KILL_POINTS)
        # ciclo completo: 3 ondate con RIPOSIZIONAMENTO (celle nuove)
        var wave1: Array[Vector2i] = hz.scroll_chasm_cells()
        var advances: int = 0
        for _i in 400:
                hz.update_hazards(50.0, main.maze)
                advances += 1
                if hz.scroll_chasm_list.is_empty() and hz.scroll_chasm_waves_left <= 0:
                        break
        if not hz.scroll_chasm_list.is_empty() or hz.scroll_chasm_waves_left != 0:
                _fail("E: ciclo non concluso (lista %d, waves %d, %d step)"
                                % [hz.scroll_chasm_list.size(),
                                        hz.scroll_chasm_waves_left, advances])
        elif wave1.is_empty():
                _fail("E: precondizione ondata 1 mancante")
        else:
                _ok("E: 3 ondate complete in %d step (~%.1fs simulati), tutto pulito"
                                % [advances, advances * 50.0 / 1000.0])


# ===========================================================================
# F — SCADENZA: 16s + 2s blink (18s totali, +50% TASK 41), poi scompare;
# TASK 36: se non usata puo' riapparire (max 2 per livello), se il budget
# e' esaurito -> DONE
# ===========================================================================
func _phaseF_expiry() -> void:
        main.scroll_quake_phase = main.ScrollPhase.GROUND
        var cell_ok: Vector2i = main._random_empty_cell()
        main.scroll_quake_item = main._create_collectible(
                        main.CollectiblesClass.Kind.QUAKE_SCROLL,
                        main._cell_to_pixel(cell_ok))
        main.scroll_quake_item.scroll_lifetime_ms = float(
                        C.PARCHMENT_VISIBLE_MS + C.PARCHMENT_BLINK_MS)
        main.collectibles_node.add_child(main.scroll_quake_item)
        var item = main.scroll_quake_item
        # simula il trascorrere del tempo (il blink vive nel Collectibles)
        var saw_blink: bool = false
        var alive_at_old_lifetime: bool = false
        for _i in 190:
                item.update_step(100.0, Vector2(9999, 9999), 1)
                if item.modulate.a < 1.0:
                        saw_blink = true
                # TASK 41: al VECCHIO limite (12s) la pergamena deve essere
                # ancora raccoglibile — il +50% porta il totale a 18s
                if _i == 119 and item.active:
                        alive_at_old_lifetime = true
        if item.active:
                _fail("F: pergamena ancora attiva dopo 19s di vita")
        elif not alive_at_old_lifetime:
                _fail("F: pergamena scaduta entro i vecchi 12s (+50% non applicato)")
        elif not saw_blink:
                _fail("F: lampeggio finale mai visto")
        else:
                _ok("F: 16s visibile + 2s di lampeggio (18s totali, +50%), poi active=false")
        # TASK 36: scaduta NON raccolta (era la 1a apparizione) -> il tipo
        # torna WAIT e programma la SECONDA apparizione (finestra 15-45s)
        main.scroll_quake_spawns_used = 1
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.WAIT:
                _fail("F: scadenza non usata non riprogramma la 2a apparizione (fase %d)"
                                % main.scroll_quake_phase)
        elif main.scroll_quake_timer_ms < float(C.PARCHMENT_NEXT_MIN_MS) \
                        or main.scroll_quake_timer_ms > float(C.PARCHMENT_NEXT_MAX_MS):
                _fail("F: timer 2a apparizione fuori finestra (%.0f)"
                                % main.scroll_quake_timer_ms)
        elif main.scroll_quake_item != null:
                _fail("F: nodo pergamena non liberato")
        else:
                _ok("F: scaduta non usata -> 2a apparizione tra %.0fs"
                                % (main.scroll_quake_timer_ms / 1000.0))
        # TASK 36: budget esaurito (2/2) -> la prossima scadenza chiude DONE
        main.scroll_quake_phase = main.ScrollPhase.GROUND
        var cell2: Vector2i = main._random_empty_cell()
        main.scroll_quake_item = main._create_collectible(
                        main.CollectiblesClass.Kind.QUAKE_SCROLL,
                        main._cell_to_pixel(cell2))
        main.scroll_quake_item.scroll_lifetime_ms = 1.0
        main.collectibles_node.add_child(main.scroll_quake_item)
        main.scroll_quake_item.update_step(100.0, Vector2(9999, 9999), 1)
        main.scroll_quake_spawns_used = 2
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.DONE:
                _fail("F: budget esaurito ma evento non chiuso (fase %d)"
                                % main.scroll_quake_phase)
        else:
                _ok("F: 2/2 apparizioni consumate -> evento chiuso (DONE)")


# ===========================================================================
# G — (TASK 36) SECONDA APPARIZIONE REALE + guardia budget
# ===========================================================================
func _phaseG_second_spawn() -> void:
        # livello fresco (i nemici di E/F potrebbero essere sotto il 30%)
        main.start_level(10)
        main.scroll_chasm_phase = main.ScrollPhase.DONE
        main.scroll_quake_spawns_used = 1   # 1a apparizione gia' consumata
        main.scroll_quake_phase = main.ScrollPhase.WAIT
        main.scroll_quake_timer_ms = 1.0
        main._update_parchments(16.0)   # -> BEACON (1 < 2, vivi al 100%)
        main.scroll_quake_timer_ms = 1.0
        main._update_parchments(16.0)   # -> GROUND (2a apparizione REALE)
        if main.scroll_quake_phase != main.ScrollPhase.GROUND \
                        or main.scroll_quake_item == null:
                _fail("G: seconda apparizione negata (fase %d)"
                                % main.scroll_quake_phase)
        elif main.scroll_quake_spawns_used != 2:
                _fail("G: contatore apparizioni %d, atteso 2"
                                % main.scroll_quake_spawns_used)
        else:
                _ok("G: seconda apparizione a terra (2/2, lifetime %.0fs)"
                                % (main.scroll_quake_item.scroll_lifetime_ms / 1000.0))
        # la fa scadere: budget esaurito -> DONE, MAI una terza apparizione
        main.scroll_quake_item.active = false
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.DONE:
                _fail("G: terza apparizione programmata (fase %d)"
                                % main.scroll_quake_phase)
        else:
                _ok("G: scadenza della 2a -> evento chiuso, mai una terza")
        # guardia budget: WAIT con budget esaurito -> DONE immediato
        main.scroll_quake_phase = main.ScrollPhase.WAIT
        main.scroll_quake_timer_ms = 1.0
        main._update_parchments(16.0)
        if main.scroll_quake_phase != main.ScrollPhase.DONE:
                _fail("G: WAIT col budget esaurito non chiude subito (fase %d)"
                                % main.scroll_quake_phase)
        else:
                _ok("G: guardia budget in WAIT -> DONE immediato")


# ===========================================================================
# H — ROLLBACK
# ===========================================================================
func _phaseH_rollback() -> void:
        C.PARCHMENTS_ENABLED = false
        main.start_level(10)
        if main.scroll_quake_phase != main.ScrollPhase.DONE \
                        or main.scroll_chasm_phase != main.ScrollPhase.DONE:
                _fail("H: PARCHMENTS_ENABLED=false ma pergamene programmate (%d/%d)"
                                % [main.scroll_quake_phase, main.scroll_chasm_phase])
        else:
                _ok("H: rollback — nessuna pergamena programmata")
        C.PARCHMENTS_ENABLED = true


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] TUTTI I TEST PERGAMENE SUPERATI")
                get_tree().quit(0)
        else:
                print("[TEST] %d TEST PERGAMENE FALLITI:" % failures.size())
                for f in failures:
                        print("  - ", f)
                get_tree().quit(1)

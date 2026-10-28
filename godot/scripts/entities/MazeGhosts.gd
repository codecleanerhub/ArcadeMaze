## MazeGhosts.gd - TASK 81.1 + 81c: FANTASMI LENZUOLO del labirinto.
## ============================================================
## Meccanica (richiesta utente + correzioni):
##   * Fantasmi di colore BIANCO, ROSSO e VERDE trasparente, in stile
##     classico lenzuolo con occhi e bocca, che fluttuano a mezz'aria.
##   * Escono da un muro del labirinto, ATTRAVERSANO IL CORRIDOIO davanti
##     a quella faccia di muro e si compenetrano nel muro opposto,
##     sparendo ("arrivano all'estremo successivo del muro,
##     compenetrandosi nel muro e sparendo").
##   * Sono IMMORTALI (i proiettili passano attraverso) ma DANNOSI: il
##     tocco toglie il 33% dell'energia max (Player.take_hazard_damage,
##     pattern ganasce: bypassa le armature, rispetta invulnerabilita'
##     post-colpo/calice/spawn). Il SALTO EVITA il tocco: il lenzuolo
##     occupa la mezzeria del corridoio e il player lo supera saltandoci
##     SOPRA ("il player li puo' evitare saltandoli").
##
## TASK 81c (richiesta utente) — RESPAWN INFINITO A ONDATE:
##   * "Respawnano per tutto il tempo, non per un numero di volte
##     limitato": NIENTE budget di apparizioni, le ondate non finiscono
##     mai per tutta la durata del livello.
##   * Cambia la COMPOSIZIONE e il RITMO col livello
##     (GameConstants.ghost_wave_size / ghost_wave_respawn_ms):
##       - L1:  UN lenzuolo per ondata, colore in ROTAZIONE (bianco ->
##              rosso -> verde -> bianco...), prossima ondata 30s dopo
##              la scomparsa nel muro opposto;
##       - L2:  DUE lenzuoli insieme ([bianco, rosso] -> [verde, bianco]
##              -> [rosso, verde]...), prossima ondata dopo 25s;
##       - L2-6: due per ondata, ritmo -5s per livello (20/15/10s);
##       - L6+: ritmo al minimo di 5s ("dopo pochissimo tempo");
##       - L7+: TRE lenzuoli per ondata — "tutti e 3 insieme e
##              respawneranno insieme dopo pochissimo tempo".
##   * Il delay parte quando l'ULTIMO lenzuolo dell'ondata e' scomparso
##     ("sparisce contro il muro opposto e DOPO 30 secondi appare il
##     fantasma rosso"): ondate strettamente sequenziali.
##   * Un fantasma non ri-usa SUBITO lo stesso muro (last_run_key), per
##     conservare il "respawnano da un altro muro" della spec originale.
##
## Rendering: sheet PixelLab 256x64 (4 frame di float) per colore,
## env/ghost_sheet_{white,red,green}.png — bianco nativo + rosso/verde
## tint per-canale (pattern 61b, task81_integrate.py). Un solo nodo con
## _draw() unico per tutti i fantasmi attivi (1 canvas item, costo minimo);
## il nodo sta DOPO Collectibles in MainGame.tscn cosi' i lenzuoli
## fluttuano SOPRA muri, player e nemici ("a mezz'aria").
##
## Movimento: il fantasma percorre la mezzeria del CORRIDOIO tra due muri
## statici affacciati (cella corridoio con muro su entrambi i lati di un
## asse): centro del muro A -> centro del corridoio -> centro del muro B
## (128px). Emergere/affondare = ramp di alpha sui primi/ultimi 28px
## dentro la roccia; il tocco dannoso vale solo quando il lenzuolo e'
## EMERSO nel corridoio (finestra di piena visibilita').
## ============================================================
extends Node2D
class_name MazeGhosts

const C = preload("res://scripts/core/GameConstants.gd")

# Dimensione rendering del lenzuolo: sotto i nemici (78px, gerarchia
# sprite: player 83 > miniboss 82 > nemici 78 > tesori 73.6) per non
# coprire il gameplay, sopra i muri che attraversa.
const GHOST_DRAW_SIZE: float = 72.0
# Lunghezza (px) dei ramp di comparsa/sparizione nel muro.
const EMERGE_LEN_PX: float = 28.0
# Durata frame dello sheet di float (4 frame).
const FRAME_MS: int = 150

# --- Sheet PixelLab (cache static: 3 upload GPU a vita) ---
static var _sheet_cache: Dictionary = {}  # color key -> Texture2D
static var _sheet_tried: bool = false

const COLORS: Array = ["white", "red", "green"]

# --- Stato del sistema ---
var _level: int = 1
var _time_ms: float = 0.0
var _ghosts: Array = []  # dizionari-stato per fantasma (3: W/R/G fissi)
var _crossings: Array = []  # segmenti muro-A/corridoio/muro-B attraversabili
var _rng := RandomNumberGenerator.new()

# --- TASK 81c: stato dello scheduler a ondate ---
# Un'ondata e' "in volo" dallo spawn finche' l'ultimo lenzuolo non e'
# scomparso nel muro opposto; SOLO allora parte il conteggio del delay.
var _wave_flying: bool = false
var _next_wave_ms: float = 0.0  # countdown alla prossima ondata
var _color_wheel: int = 0  # rotazione colori (avanza di 1 per lenzuolo)
var _total_runs: int = 0  # attraversamenti completati in totale (stat)


## Carica (una volta) gli sheet dei 3 colori. Null = fallback: il fantasma
## non disegna lo sprite (ma la logica continua: e' atmosfera, non gameplay).
static func _get_sheet(color: String) -> Texture2D:
        if _sheet_cache.has(color):
                return _sheet_cache[color]
        if not _sheet_tried:
                _sheet_tried = true
                for col in ["white", "red", "green"]:
                        var path := "res://assets/sprites/env/ghost_sheet_%s.png" % col
                        if FileAccess.file_exists(path):
                                var img := Image.load_from_file(path)
                                if img != null:
                                        _sheet_cache[col] = ImageTexture.create_from_image(img)
        return _sheet_cache.get(color)


## Genera il pool fantasmi per il livello. Chiamato da
## MainGameController.start_level() dopo maze.generate(). RNG seedato sul
## livello (gli orari degli spawn si ripetono al continue, pattern hazards).
func generate(lvl: int, maze: Node) -> void:
        _ghosts.clear()
        _crossings.clear()
        _level = lvl
        _time_ms = 0.0
        _wave_flying = false
        _color_wheel = 0
        _total_runs = 0
        if not C.GHOSTS_ENABLED:
                queue_redraw()
                return
        _rng.seed = hash("mghosts_v3_%d" % lvl)
        _collect_crossings(maze)
        if _crossings.is_empty():
                queue_redraw()
                return
        # TASK 81c: pool FISSO dei 3 lenzuoli (bianco, rosso, verde) —
        # respawnano per sempre, nessun budget da inizializzare.
        for i in range(mini(C.GHOST_POOL_SIZE, COLORS.size())):
                _ghosts.append({
                        "color": COLORS[i],
                        "active": false,
                        "pos": Vector2.ZERO,
                        "dir": Vector2.RIGHT,
                        "travel_left": 0.0,
                        "travel_total": 0.0,
                        "phase": _rng.randf() * TAU,  # fase bob indipendente
                        "last_run_key": "",  # muro dell'attraversamento precedente
                })
        # prima ondata scaglionata: 1.5-4s dall'avvio del livello
        _next_wave_ms = _rng.randf_range(
                        C.GHOST_FIRST_SPAWN_MIN_MS, C.GHOST_FIRST_SPAWN_MAX_MS)
        queue_redraw()


## CORREZIONE UTENTE (attraversamento del corridoio): raccoglie i punti
## di attraversamento = celle CORRIDOIO (non WALL, quindi anche tesori/armi
## a terra: il lenzuolo ci fluttua sopra) con muro STATICO su entrambi i
## lati lungo un asse cardinale. Il fantasma emerge dal centro del muro A,
## attraversa la mezzeria del corridoio e si compenetra nel muro B:
## e' l'unica geometria in cui "il player li puo' saltare" ha senso (il
## lenzuolo blocca il corridoio su cui cammina il player).
## Esclusioni: celle delle gallerie Pac-Man (bordo), muri dinamici Task 30
## (le lastre si aprono: il muro d'arrivo scomparirebbe a meta' strada).
func _collect_crossings(maze: Node) -> void:
        if maze == null:
                return
        var axes: Array = [Vector2i(1, 0), Vector2i(0, 1)]
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        # cella corridoio reale (le lastre mobili del Task 30
                        # hanno tipo statico WALL anche quando aperte:
                        # restano escluse qui)
                        if maze.get_cell_type(c, r) == C.CellType.WALL:
                                continue
                        if C.is_tunnel_cell(c, r):
                                continue
                        for a in axes:
                                var wa: Vector2i = Vector2i(c, r) - a
                                var wb: Vector2i = Vector2i(c, r) + a
                                if _is_static_wall(maze, wa) and _is_static_wall(maze, wb):
                                        _crossings.append({
                                                "key": "%d,%d|%d,%d" % [wa.x, wa.y, wb.x, wb.y],
                                                "start": Vector2(
                                                                wa.x * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                                                                C.UI_HEIGHT + wa.y * C.TILE_SIZE + C.TILE_SIZE * 0.5),
                                                "end": Vector2(
                                                                wb.x * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                                                                C.UI_HEIGHT + wb.y * C.TILE_SIZE + C.TILE_SIZE * 0.5),
                                        })


## Muro pieno, in griglia, non mobile (lastre Task 30: si aprono).
func _is_static_wall(maze: Node, cell: Vector2i) -> bool:
        if cell.x < 0 or cell.x >= C.MAZE_COLS or cell.y < 0 or cell.y >= C.MAZE_ROWS:
                return false
        if maze.get_cell_type(cell.x, cell.y) != C.CellType.WALL:
                return false
        return not maze.dynamic_walls.has("%d,%d" % [cell.x, cell.y])


## Update del sistema (chiamato da MainGameController._update_playing).
## CORREZIONE UTENTE: `players` = i player VIVI (per il tocco dannoso
## -33% energia; il salto protegge dentro Player.take_hazard_damage).
func update_ghosts(delta_ms: float, players: Array = []) -> void:
        _time_ms += float(delta_ms)
        if _ghosts.is_empty():
                return
        var step_px: float = C.GHOST_SPEED_PX_S * float(delta_ms) * 0.001
        var any_active: bool = false
        for g in _ghosts:
                if g["active"]:
                        _advance_crossing(g, step_px, players)
                        any_active = true
        # -------- TASK 81c: scheduler a ondate sequenziali --------
        # Mentre un'ondata e' in volo NON parte nessun countdown; quando
        # l'ultimo lenzuolo e' scomparso nel muro opposto, il delay della
        # prossima ondata parte in QUEL momento ("sparisce contro il muro
        # opposto e DOPO 30 secondi appare il prossimo").
        if not any_active:
                if _wave_flying:
                        _wave_flying = false
                        _next_wave_ms = C.ghost_wave_respawn_ms(_level)
                else:
                        _next_wave_ms -= float(delta_ms)
                        if _next_wave_ms <= 0.0:
                                _spawn_wave()
        queue_redraw()


func _count_active() -> int:
        var n: int = 0
        for g in _ghosts:
                if g["active"]:
                        n += 1
        return n


## TASK 81c: lancia l'ondata del livello corrente — ghost_wave_size(level)
## lenzuoli INSIEME, colori consecutivi dalla rotazione (_color_wheel),
## ognuno su un crossing DISTINTO (shuffle seedato) e diverso dal muro
## usato la volta precedente (last_run_key).
func _spawn_wave() -> void:
        var w: int = mini(mini(C.ghost_wave_size(_level), _ghosts.size()),
                        _crossings.size())
        if w <= 0:
                # labirinto degenere (o fantasmi gia' tutti in volo per via
                # dei force_launch dei test): riprova tra poco
                _next_wave_ms = 1500.0
                return
        var pool: Array = _crossings.duplicate()
        _shuffle_seeded(pool)
        var taken: Array = []  # crossing usati da QUESTA ondata
        var launched: int = 0
        for i in range(w):
                var g: Dictionary = _ghosts[(_color_wheel + i) % _ghosts.size()]
                if g["active"]:
                        continue  # (force_launch dei test) resta in volo
                var cross: Dictionary = _pick_crossing(pool, g, taken)
                if cross.is_empty():
                        break
                if _launch_crossing(g, cross):
                        launched += 1
                        taken.append(cross["key"])
        # la rotazione avanza di tanti passi quanti i lenzuoli SPAWNATI:
        # L1 bianco -> rosso -> verde; L2 [W,R] -> [G,W] -> [R,G]...
        _color_wheel = (_color_wheel + launched) % _ghosts.size()
        _wave_flying = launched > 0
        if not _wave_flying:
                _next_wave_ms = 1500.0  # tutti occupati: riprova tra poco


## Primo crossing dello shuffle che non sia gia' preso dall'ondata e non
## sia il muro dell'uscita precedente di questo fantasma ("la volta
## successiva respawnano da un ALTRO muro"); fallback: il primo libero.
func _pick_crossing(pool: Array, g: Dictionary, taken: Array) -> Dictionary:
        var fallback: Dictionary = {}
        for cross in pool:
                if taken.has(cross["key"]):
                        continue
                if fallback.is_empty():
                        fallback = cross
                if cross["key"] != g["last_run_key"]:
                        return cross
        return fallback


## Fisher-Yates con l'RNG seedato del livello (determinismo del continue:
## stessa sequenza di shuffle a parita' di livello e di ondate).
func _shuffle_seeded(arr: Array) -> void:
        for i in range(arr.size() - 1, 0, -1):
                var j: int = _rng.randi_range(0, i)
                var tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp


## Lancia la traversata del fantasma `g` sul crossing `cross`
## (muro A -> corridoio -> muro B; la direzione e' quella dell'asse).
func _launch_crossing(g: Dictionary, cross: Dictionary) -> bool:
        var start: Vector2 = cross["start"]
        var end: Vector2 = cross["end"]
        var travel: float = start.distance_to(end)
        if travel < 1.0:
                return false
        g["active"] = true
        g["pos"] = start
        g["dir"] = (end - start).normalized()
        g["travel_total"] = travel
        g["travel_left"] = travel
        g["run_key"] = cross["key"]
        return true


## Avanza l'attraversamento; alla fine il lenzuolo resta pronto per la
## PROSSIMA ondata (respawn infinito TASK 81c: nessun budget).
## CORREZIONE UTENTE: mentre il lenzuolo e' EMERSO nel corridoio (fuori dai
## ramp di alpha sui muri) tocca i player VIVI entro GHOST_TOUCH_RADIUS_PX:
## -33% energia max per tocco (Player.take_hazard_damage: bypassa le
## armature come le ganasce, il SALTO e l'invulnerabilita' post-colpo
## proteggono — "il player li puo' evitare saltandoli").
func _advance_crossing(g: Dictionary, step_px: float, players: Array) -> void:
        g["travel_left"] = maxf(0.0, g["travel_left"] - step_px)
        g["pos"] = g["pos"] + g["dir"] * step_px
        var traveled: float = g["travel_total"] - g["travel_left"]
        # --- Tocco dannoso: solo con il lenzuolo nel corridoio ---
        if not players.is_empty() \
                        and traveled >= EMERGE_LEN_PX \
                        and g["travel_left"] >= EMERGE_LEN_PX:
                for p in players:
                        if p == null or not is_instance_valid(p):
                                continue
                        if (p.position as Vector2).distance_to(g["pos"]) \
                                        <= C.GHOST_TOUCH_RADIUS_PX:
                                var dmg: int = maxi(1, int(round(
                                                float(p.max_energy)
                                                * C.GHOST_TOUCH_DAMAGE_PCT)))
                                p.take_hazard_damage(dmg)
        if traveled >= g["travel_total"]:
                g["active"] = false
                g["last_run_key"] = g["run_key"]
                _total_runs += 1
                g["pos"] = Vector2.ZERO


func _draw() -> void:
        if _ghosts.is_empty():
                return
        var t: float = _time_ms * 0.001
        for g in _ghosts:
                if not g["active"]:
                        continue
                var tex: Texture2D = _get_sheet(g["color"])
                if tex == null:
                        continue
                var traveled: float = g["travel_total"] - g["travel_left"]
                # alpha: ramp di comparsa/sparizione nel muro (i primi/ultimi
                # 28px), al centro pulsazione spettrale attorno a 0.72.
                var alpha: float
                if traveled < EMERGE_LEN_PX:
                        alpha = traveled / EMERGE_LEN_PX
                elif g["travel_left"] < EMERGE_LEN_PX:
                        alpha = g["travel_left"] / EMERGE_LEN_PX
                else:
                        alpha = 1.0
                alpha *= 0.72 + 0.06 * sin(t * 2.6 + g["phase"])
                alpha = clampf(alpha, 0.0, 1.0)
                # fluttuazione a mezz'aria
                var bob_y: float = sin(t * 2.2 + g["phase"]) * 4.0
                var sway_x: float = sin(t * 1.5 + g["phase"] * 0.7) * 2.0
                var frame: int = (int(_time_ms) / FRAME_MS) % 4
                var src := Rect2(float(frame) * 64.0, 0.0, 64.0, 64.0)
                var dst := Rect2(
                                g["pos"].x - GHOST_DRAW_SIZE * 0.5 + sway_x,
                                g["pos"].y - GHOST_DRAW_SIZE * 0.5 + bob_y,
                                GHOST_DRAW_SIZE, GHOST_DRAW_SIZE)
                draw_texture_rect_region(tex, dst, src, Color(1.0, 1.0, 1.0, alpha), false, false)


# ============================================================================
# API di introspezione (per i test headless tests/test_maze81.gd)
# ============================================================================
func ghost_count() -> int:
        return _ghosts.size()


func active_count() -> int:
        return _count_active()


## TASK 81c: attraversamenti COMPLETATI da quando e' iniziato il livello
## (respawn infinito: cresce senza limite, mai "budget esaurito").
func total_runs() -> int:
        return _total_runs


## TASK 81c: stato dello scheduler a ondate (sola lettura, per i test):
## flying = ondata in volo, next_ms = countdown alla prossima ondata,
## wheel = posizione della rotazione colori.
func wave_info() -> Dictionary:
        return {
                "flying": _wave_flying,
                "next_ms": _next_wave_ms,
                "wheel": _color_wheel,
        }


## Attraversamenti (muro-A|corridoio|muro-B) disponibili nel livello.
func crossing_count() -> int:
        return _crossings.size()


## TEST HOOK (correzione utente): stato del fantasma attivo `idx` nel pool
## (dict interno, sola lettura) — per verificare pos/direzioni nei test.
func ghost_state(idx: int) -> Dictionary:
        if idx < 0 or idx >= _ghosts.size():
                return {}
        return _ghosts[idx]


## TEST HOOK (correzione utente): lancia immediatamente l'attraversamento
## del fantasma `idx` su un crossing casuale (scavalca il timer di spawn)
## e ne ritorna lo stato. L'ondata forzata conta come "in volo": lo
## scheduler non spawnera' altro finche' non e' finita (+ delay di livello).
func force_launch(idx: int) -> Dictionary:
        if idx < 0 or idx >= _ghosts.size():
                return {}
        var g: Dictionary = _ghosts[idx]
        if not bool(g["active"]):
                var pool: Array = _crossings.duplicate()
                _shuffle_seeded(pool)
                var cross: Dictionary = _pick_crossing(pool, g, [])
                if cross.is_empty():
                        cross = pool[0] if not pool.is_empty() else {}
                if not cross.is_empty() and _launch_crossing(g, cross):
                        _wave_flying = true
        return g

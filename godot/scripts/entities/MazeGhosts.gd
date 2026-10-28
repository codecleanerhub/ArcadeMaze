## MazeGhosts.gd - TASK 81.1: FANTASMI LENZUOLO del labirinto.
## ============================================================
## Meccanica (richiesta utente + CORREZIONE utente: "non devono essere
## innocui, il player li puo' evitare saltandoli ma se toccono il player
## levano il 33% dell'energia"):
##   * Fantasmi di colore BIANCO, ROSSO e VERDE trasparente, in stile
##     classico lenzuolo con occhi e bocca, che fluttuano a mezz'aria.
##   * Escono da un muro del labirinto in tempi casuali, ATTRAVERSANO
##     IL CORRIDOIO davanti a quella faccia di muro e si compenetrano
##     nel muro opposto, sparendo ("arrivano all'estremita' successiva
##     del muro, compenetrandosi nel muro e sparendo").
##   * Sono IMMORTALI (i proiettili passano attraverso) ma DANNOSI: il
##     tocco toglie il 33% dell'energia max (Player.take_hazard_damage,
##     pattern ganasce: bypassa le armature, rispetta invulnerabilita'
##     post-colpo/calice/spawn). Il SALTO EVITA il tocco: il lenzuolo
##     occupa la mezzeria del corridoio e il player lo supera saltandoci
##     SOPRA ("il player li puo' evitare saltandoli").
##   * La volta successiva respawnano da un ALTRO muro: ogni fantasma ha
##     un budget di 3 apparizioni su 3 MURI DIVERSI, poi non appare piu'.
##   * Fino a 4 fantasmi simultanei; la probabilita' che siano 4 in
##     schermo aumenta col livello (GameConstants.ghost_allowed_simultaneous).
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
var _ghosts: Array = []  # dizionari-stato per fantasma
var _crossings: Array = []  # segmenti muro-A/corridoio/muro-B attraversabili
var _rng := RandomNumberGenerator.new()


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
        if not C.GHOSTS_ENABLED:
                queue_redraw()
                return
        _rng.seed = hash("mghosts_v2_%d" % lvl)
        _collect_crossings(maze)
        if _crossings.is_empty():
                queue_redraw()
                return
        # Pool: bianco, rosso, verde + un quarto colore random (richiesta:
        # "fino a 4 fantasmi contemporaneamente" = pool di 4 lenzuoli).
        var pool_colors: Array = ["white", "red", "green"]
        pool_colors.append(COLORS[_rng.randi() % COLORS.size()])
        for i in range(mini(C.GHOST_POOL_SIZE, pool_colors.size())):
                _ghosts.append({
                        "color": pool_colors[i],
                        "appearances_left": C.GHOST_MAX_APPEARANCES,
                        "used_run_keys": [],
                        # prima uscita scaglionata: 1.5-4s dall'avvio livello
                        "next_spawn_ms": _rng.randf_range(
                                        C.GHOST_FIRST_SPAWN_MIN_MS, C.GHOST_FIRST_SPAWN_MAX_MS),
                        # stato attraversamento (valido solo se active)
                        "active": false,
                        "pos": Vector2.ZERO,
                        "dir": Vector2.RIGHT,
                        "travel_left": 0.0,
                        "travel_total": 0.0,
                        "phase": _rng.randf() * TAU,  # fase bob indipendente
                })
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
        var active_count: int = _count_active()
        var step_px: float = C.GHOST_SPEED_PX_S * float(delta_ms) * 0.001
        for g in _ghosts:
                if g["active"]:
                        _advance_crossing(g, step_px, players)
                        continue
                # IDLE: budget esaurito -> ritirato per sempre
                if g["appearances_left"] <= 0:
                        continue
                g["next_spawn_ms"] -= float(delta_ms)
                if g["next_spawn_ms"] > 0.0:
                        continue
                # cap simultaneo probabilistico (sale col livello)
                if active_count >= 1 \
                                and active_count >= C.ghost_allowed_simultaneous(_level):
                        # spawn rimandato: riprova tra poco
                        g["next_spawn_ms"] = _rng.randf_range(1200.0, 2500.0)
                        continue
                if _launch_crossing(g):
                        active_count += 1
        queue_redraw()


func _count_active() -> int:
        var n: int = 0
        for g in _ghosts:
                if g["active"]:
                        n += 1
        return n


## Sceglie un attraversamento NON ancora usato da questo fantasma e lancia
## la traversata (muro A -> corridoio -> muro B; la direzione e' quella
## dell'asse del crossing). Ritorna false se non ci sono crossing nuovi
## (fantasma ritirato in anticipo, caso limite).
func _launch_crossing(g: Dictionary) -> bool:
        var candidates: Array = []
        for cross in _crossings:
                if not (g["used_run_keys"] as Array).has(cross["key"]):
                        candidates.append(cross)
        if candidates.is_empty():
                g["appearances_left"] = 0
                return false
        var cross: Dictionary = candidates[_rng.randi() % candidates.size()]
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


## Avanza l'attraversamento; alla fine consuma un'apparizione e segna il
## muro come usato ("la volta successiva respawnano da un altro muro").
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
                g["appearances_left"] -= 1
                (g["used_run_keys"] as Array).append(g["run_key"])
                if g["appearances_left"] > 0:
                        g["next_spawn_ms"] = C.ghost_spawn_interval_ms(_level)
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


func appearances_left(color: String) -> int:
        for g in _ghosts:
                if g["color"] == color:
                        return int(g["appearances_left"])
        return -1


func total_appearances_left() -> int:
        var n: int = 0
        for g in _ghosts:
                n += int(g["appearances_left"])
        return n


func used_run_keys_of(color: String) -> Array:
        for g in _ghosts:
                if g["color"] == color:
                        return g["used_run_keys"]
        return []


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
## del fantasma `idx` (scavalca il timer di spawn; la coerenza cap/budget
## resta a carico del chiamante) e ne ritorna lo stato.
func force_launch(idx: int) -> Dictionary:
        if idx < 0 or idx >= _ghosts.size():
                return {}
        var g: Dictionary = _ghosts[idx]
        if not bool(g["active"]) and int(g["appearances_left"]) > 0:
                _launch_crossing(g)
        return g

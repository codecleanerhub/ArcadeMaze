## MazeHazards.gd - TASK 30: hazard ambientali del labirinto.
## =============================================================
## Quattro pericoli generati a ogni livello maze (dal livello 4, in
## quantita' crescente ogni 3 livelli, max 4 per tipo — Task 34):
##
##   * SABBIE MOBILI (quicksand): cella che rallenta il player del 50%
##     (i nemici passano indenni). Si superano con un salto. Gli stivali
##     della velocita' annullano il malus.
##   * GANASCE (trap): trappola dentata ARMATA visibile a terra. Cattura
##     il player che la calpesta (grounded): -33% energia max (morte se
##     l'energia residua non basta), tenuta 1.5s accorciabile MASHANDO
##     salto/sparo (min 0.6s). TASK 34 (richiesta utente): una volta che
##     scatta la ganascia si DISATTIVA per il resto del livello — puo'
##     colpire il player UNA SOLA volta. Un PROIETTILE del player la fa
##     scattare a vuoto: disattivata anche in quel caso (sparare alle
##     ganasce le bonifica: elemento di skill).
##   * VORAGINE (chasm): appare con telegrafo (crepa + rumble, 1.2s) poi
##     resta APERTA per tutto il livello: chi vi cade dentro perde una
##     vita (salto = passi sopra; ghost = immuni; i nemici camminano sul
##     bordo indenni).
##   * MURO DI ROCCIA (rock wall): cella muro TRA DUE CORRIDOI che si
##     apre/chiude (3s aperto + 0.5s vibrazione + 3s chiuso): scorciatoia
##     per player E nemici quando APERTO (il BFS la attraversa). TASK 34
##     (richiesta utente): CHIUSO il muro blocca ANCHE I NEMICI — un
##     nemico a meta' transito verso la cella che si chiude si FERMA e
##     rientra al centro della cella di provenienza (mai compenetrazione
##     nella roccia). Chi resta imprigionato alla chiusura: player -66%
##     energia max (morte se non basta) e resta bloccato fino alla
##     riapertura; nemico -33% HP max, bloccato finche' chiuso. Nemico
##     UCCISO dal muro = 2x punti (10000) al player vivo piu' vicino.
##
## REGOLE COMUNI (decisioni utente):
##   - I danni ambientali BYPASSANO le armature-reliquia (vanno dritti
##     all'energia): le cariche armatura restano per il combattimento.
##   - Calice (invincibilita'): niente DANNO, ma le ganasce trattengono.
##   - Ghost mode / salto in corso: immuni a tutto (si vola sopra).
##   - GhostReaper e alleati ignorano gli hazard.
##   - RNG dedicato seedato per livello: stesso livello = stessi hazard
##     (determinismo per test e continue).
##   - Rollback: GameConstants.HAZARDS_ENABLED = false.
##
## Il nodo va tra Maze e Player nel tree di MainGame (draw order:
## pavimento -> hazard -> entita'). Le celle dei muri di roccia sono
## registrate in Maze.dynamic_walls cosi' is_wall/BFS/proiettili le
## vedono chiuse/aperte in tempo reale.
extends Node2D
class_name MazeHazards

const C = preload("res://scripts/core/GameConstants.gd")

enum HazardType { QUICKSAND, TRAP, CHASM, ROCK_WALL, BARREL, BLADE, SPEAR }

# Stati per tipo:
# QUICKSAND: nessuno stato (sempre attiva).
# TRAP (TASK 34):  ARMED -> SNAPPED (tieni player) -> SPRUNG (per sempre)
#                 ARMED -> SPRUNG (scatto a vuoto da proiettile)
#                 SPRUNG = scattata e DISATTIVATA: innocua, resta a terra
#                 come relitto visibile per tutto il livello. Il player puo'
#                 essere colpito UNA SOLA volta da ogni ganascia.
# CHASM:       DORMANT(delay casuale) -> CRACK(1.2s) -> OPEN (per sempre)
# ROCK_WALL:   fase ciclica OPEN(3s) -> WARN(0.5s) -> CLOSED(3s) -> OPEN...
enum TrapState { ARMED, SNAPPED, SPRUNG }
enum ChasmState { DORMANT, CRACK, OPEN }
enum WallPhase { OPEN, WARN, CLOSED }
# TASK 89 — LANCE: punte appena visibili -> VIBRAZIONE (avviso) ->
# EMERSSIONE -> FUORI 5s (infisse, danno unblockable) -> VIBRAZIONE ->
# RIENTRO -> pausa casuale.
enum SpearState { HIDDEN, WARN, RISING, UP, RETRACT_WARN, RETRACTING }

## Referenza al MainGameController (player/player2/spawner/collectible check).
var controller: Node = null

## Lista hazard: Dictionary per elemento.
## Campi comuni: type, cell (Vector2i), sprite (Sprite2D).
## TRAP: state, timer_ms, holding (CharacterBody2D|null), hold_ms.
## CHASM: state, timer_ms, delay_ms.
## ROCK_WALL: phase, phase_ms, axis ("h" passaggio orizzontale / "v"),
##            slab_a/slab_b (Sprite2D), off_a/off_b (offset attuali px).
var hazard_list: Array[Dictionary] = []

# --- TASK 31: stato del terremoto -----------------------------------------
# INACTIVE: nessun evento in programma (timer al prossimo scade).
# TELEGRAPH: rombo + scrollamento di avviso.
# DROPPING: i massi dell'evento cadono (boulder_list in giro).
enum QuakeState { INACTIVE, TELEGRAPH, DROPPING }
var quake_state: int = QuakeState.INACTIVE
var quake_timer_ms: float = 0.0
var quake_events_left: int = 0
var quake_level: int = 1
var quake_shake_accum: float = 0.0

## Massi in volo/segmentati: {cell, state (0=MARK,1=FALL), timer_ms,
## delay_ms, sprite (Sprite2D del masso o crepa), fall_from (Vector2)}.
var boulder_list: Array[Dictionary] = []

# --- TASK 35: voragini MAGICHE della pergamena -----------------------------
# 4 voragini temporanee in celle casuali ben distanziate (gap Manhattan
# >= SCROLL_CHASM_MIN_GAP): uccidono SOLO i nemici che vi entrano (il
# player e' immune). NON sono registrate in dynamic_walls: il pathing non
# le vede, i nemici ci camminano dentro e muoiono. Ogni ondata dura
# SCROLL_CHASM_WAVE_MS, poi dissolve (SCROLL_CHASM_FADE_MS) e una nuova
# ondata appare in altre celle casuali, per SCROLL_CHASM_WAVES ondate.
# {cell, sprite, state (0=OPEN, 1=FADE), timer_ms}
var scroll_chasm_list: Array[Dictionary] = []
var scroll_chasm_waves_left: int = 0
var scroll_chasm_owner: CharacterBody2D = null

# --- TASK 88: lame-ruota -----------------------------------------------------
## Corsie occupate dalle lame (righe per axis "h", colonne per "v"):
## esposte per le esclusioni dei placement successivi (lance: mai sulla
## stessa filetto di una lama) e per i test.
var blade_rows: Array[int] = []
var blade_cols: Array[int] = []
var _blade_frames: Array = []
var _spear_frames: Array = []

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _tex_cache: Dictionary = {}

# Offset (px, centro cella) delle due meta' di roccia per fase: aperto =
# retratte DENTRO i muri adiacenti (la lastra copre la cella vicina, il
# passaggio resta sgombro per ~56 dei 64px); chiuso = compenetrano al centro
# (i denti si incastrano). Il movimento e' inseguimento del target
# (SLAM px/s) cosi' la chiusura "sbatte" e l'apertura scivola. NOTA: la
# lastra e' alta ~72px (texture 226x256 scalata a 64 di larghezza), quindi
# con off 64 spunta solo 4px nella cella del passaggio.
const WALL_OPEN_OFF: float = 64.0
const WALL_CLOSED_OFF: float = 16.0
const WALL_SLAM_SPEED: float = 520.0
const WALL_JITTER: float = 2.5


# ===========================================================================
# GENERAZIONE
# ===========================================================================

## Rigenera gli hazard per il livello. Chiamato da start_level DOPO
## _spawn_collectibles (le celle occupate da item sono escluse). Il seed
## dipende solo dal livello: al continue gli hazard tornano nelle stesse
## celle con stati freschi (semplificazione voluta).
func generate(level: int, maze: Node, ctrl: Node) -> void:
        controller = ctrl
        clear(maze)
        var count: int = C.hazard_count_for_level(level)
        var barrels: int = C.barrel_count_for_level(level)
        var blades: int = C.blade_count_for_level(level)
        var spears: int = C.spear_count_for_level(level)
        if count <= 0 and barrels <= 0 and blades <= 0 and spears <= 0:
                _init_quake(level)
                return
        _rng.seed = hash("hazards_v1_%d" % level)

        var floor_cells := _collect_floor_cells(maze)
        var wall_cells := _collect_wall_cells(maze)
        var used: Array[Vector2i] = []

        # TASK 88: LAME-RUOTA — piazzate PER PRIME: il corridoio con la lama
        # reclama tutte le sue celle (entrano in `used`): gli hazard statici
        # restano a distanza di sicurezza e il player mantiene spazio di
        # manovra per saltarle. Le corsie occupate sono esposte in
        # blade_rows/blade_cols (le lance dei task successivi non finiscono
        # mai sugli stessi filetti).
        blade_rows.clear()
        blade_cols.clear()
        if blades > 0:
                var runs: Array[Dictionary] = _collect_blade_runs(maze)
                var lanes: Array[int] = []
                for _i in blades:
                        var run: Dictionary = _pop_blade_run(runs, used, lanes)
                        if run.is_empty():
                                break
                        _spawn_blade(run)
                        lanes.append(run["lane"])
                        if run["axis"] == "h":
                                blade_rows.append(run["lane"])
                                for cc in range(run["c0"], run["c1"] + 1):
                                        used.append(Vector2i(cc, run["lane"]))
                        else:
                                blade_cols.append(run["lane"])
                                for rr in range(run["c0"], run["c1"] + 1):
                                        used.append(Vector2i(run["lane"], rr))

        # TASK 89: BLOCCHI DI LANCE — dopo le lame: mai sulle loro corsie
        # ("su uno stesso pavimento non possono stare sia le lance che le
        # lame"), stesso gap minimo dagli altri hazard.
        for _i in spears:
                var spear_cell: Vector2i = _pop_spear_cell(floor_cells, used)
                if spear_cell == Vector2i(-1, -1):
                        break
                _spawn_spear(spear_cell)
                used.append(spear_cell)

        for t in [HazardType.QUICKSAND, HazardType.TRAP, HazardType.CHASM]:
                for _i in count:
                        var cell := _pop_cell(floor_cells, used, maze)
                        if cell == Vector2i(-1, -1):
                                break
                        _spawn_floor_hazard(t, cell, maze)
                        used.append(cell)

        for _i in count:
                var cell := _pop_cell(wall_cells, used, maze)
                if cell == Vector2i(-1, -1):
                        break
                _spawn_rock_wall(cell, maze)
                used.append(cell)

        # TASK 31: barili esplosivi (celle pavimento, stesso gap minimo).
        for _i in barrels:
                var cell := _pop_cell(floor_cells, used, maze)
                if cell == Vector2i(-1, -1):
                        break
                _spawn_barrel(cell)
                used.append(cell)

        _init_quake(level)


## TASK 31: programma il terremoto del livello (se il livello lo prevede).
func _init_quake(level: int) -> void:
        quake_level = level
        quake_events_left = C.quake_events_for_level(level)
        quake_state = QuakeState.INACTIVE
        quake_timer_ms = float(_rng.randi_range(
                C.QUAKE_FIRST_MIN_MS, C.QUAKE_FIRST_MAX_MS))
        quake_shake_accum = 0.0


## Rimuove tutto e ripristina lo stato di Maze/BG.
func clear(maze: Node) -> void:
        for h in hazard_list:
                if is_instance_valid(h.get("sprite")):
                        h["sprite"].queue_free()
                for key in ["slab_a", "slab_b", "trail_a", "trail_b"]:
                        if is_instance_valid(h.get(key)):
                                h[key].queue_free()
        hazard_list.clear()
        blade_rows.clear()
        blade_cols.clear()
        # TASK 31: via anche massi/macerie e stato terremoto.
        for b in boulder_list:
                if is_instance_valid(b.get("sprite")):
                        b["sprite"].queue_free()
        boulder_list.clear()
        quake_state = QuakeState.INACTIVE
        quake_events_left = 0
        # TASK 35: via anche le voragini della pergamena.
        _clear_scroll_chasms()
        if maze != null:
                maze.dynamic_walls.clear()


## Rimuove gli hazard su una cella (es. cella della porta di uscita che
## diventa attiva, o muro interno rotto dal Mjolnir).
func clear_at(cell: Vector2i, maze: Node) -> void:
        for i in range(hazard_list.size() - 1, -1, -1):
                if hazard_list[i]["type"] == HazardType.BLADE:
                        continue  # TASK 88: la lama e' mobile, non legata a una cella
                if hazard_list[i]["cell"] == cell:
                        var h: Dictionary = hazard_list[i]
                        if is_instance_valid(h.get("sprite")):
                                h["sprite"].queue_free()
                        for key in ["slab_a", "slab_b"]:
                                if is_instance_valid(h.get(key)):
                                        h[key].queue_free()
                        hazard_list.remove_at(i)
                        maze.dynamic_walls.erase(_wall_key(cell))


# --- candidate cells -------------------------------------------------------

## Celle EMPTY valide per hazard da pavimento: corridoi, lontane dallo
## spawn (1,1), non tunnel e non adiacenti agli imbocchi, non occupate da
## collectible a terra, con rispetto del gap minimo tra hazard (nel pop).
func _collect_floor_cells(maze: Node) -> Array[Vector2i]:
        var cells: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        if _near_tunnel(c, r):
                                continue
                        if max(absi(c - 1), absi(r - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                                continue
                        if controller != null \
                                        and not controller._collectible_cell_free(c, r):
                                continue
                        cells.append(Vector2i(c, r))
        return cells


## Celle WALL con ESATTAMENTE due vicini aperti OPPOSTI (E+W oppure N+S):
## sono le pareti sottili tra due corridoi — le scorciatoie vere. Bordi e
## adiacenze tunnel escluse.
func _collect_wall_cells(maze: Node) -> Array[Vector2i]:
        var cells: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.WALL:
                                continue
                        if _near_tunnel(c, r):
                                continue
                        if max(absi(c - 1), absi(r - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                                continue
                        var ew_open: bool = not maze.is_wall(c - 1, r) \
                                        and not maze.is_wall(c + 1, r)
                        var ns_open: bool = not maze.is_wall(c, r - 1) \
                                        and not maze.is_wall(c, r + 1)
                        # esattamente due vicini aperti e opposti: una delle
                        # coppie e' aperta E le altre due direzioni son muri
                        var open_n: int = int(not maze.is_wall(c - 1, r)) \
                                        + int(not maze.is_wall(c + 1, r)) \
                                        + int(not maze.is_wall(c, r - 1)) \
                                        + int(not maze.is_wall(c, r + 1))
                        if open_n != 2:
                                continue
                        if not (ew_open or ns_open):
                                continue
                        cells.append(Vector2i(c, r))
        return cells


func _near_tunnel(c: int, r: int) -> bool:
        for tc in C.TUNNEL_COLS_TOP_BOTTOM:
                if absi(c - tc) <= 1 and (r <= 2 or r >= C.MAZE_ROWS - 3):
                        return true
        # riga tunnel laterale: celle della riga e le due adiacenti
        if absi(r - C.TUNNEL_ROW_SIDES) <= 1 and (c <= 2 or c >= C.MAZE_COLS - 3):
                return true
        return false


## Estrae una cella casuale che rispetti il gap minimo dagli hazard gia'
## piazzati (Manhattan >= HAZARD_MIN_GAP).
func _pop_cell(cells: Array[Vector2i], used: Array[Vector2i], _maze: Node) -> Vector2i:
        for _attempt in 24:
                if cells.is_empty():
                        break
                var idx: int = _rng.randi_range(0, cells.size() - 1)
                var cell: Vector2i = cells[idx]
                var ok := true
                for u in used:
                        if absi(cell.x - u.x) + absi(cell.y - u.y) < C.HAZARD_MIN_GAP:
                                ok = false
                                break
                if ok:
                        cells.remove_at(idx)
                        return cell
                cells.remove_at(idx)
        return Vector2i(-1, -1)


# --- spawn dei singoli hazard ----------------------------------------------

func _cell_center(cell: Vector2i) -> Vector2:
        return Vector2(
                cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)


func _tex(path: String) -> Texture2D:
        if not _tex_cache.has(path):
                _tex_cache[path] = load(path)
        return _tex_cache[path]


func _make_sprite(tex_path: String, cell: Vector2i, px: float = C.TILE_SIZE) -> Sprite2D:
        var s := Sprite2D.new()
        s.texture = _tex(tex_path)
        s.position = _cell_center(cell)
        s.scale = Vector2(px / s.texture.get_width(), px / s.texture.get_height())
        # z_index 0 (default): l'ordine dell'albero MainGame fa il resto —
        # Maze (pavimento) -> Hazards -> Player/Enemies. Con z_index -1 gli
        # sprite finivano DIETRO il pavimento del Maze (_draw a z=0) e
        # risultavano invisibili.
        s.z_index = 0
        add_child(s)
        return s


func _spawn_floor_hazard(t: int, cell: Vector2i, maze: Node) -> void:
        var h: Dictionary = {"type": t, "cell": cell}
        match t:
                HazardType.QUICKSAND:
                        h["sprite"] = _make_sprite(
                                "res://assets/sprites/hazards/quicksand.png", cell, 66.0)
                HazardType.TRAP:
                        h["state"] = TrapState.ARMED
                        h["timer_ms"] = 0.0
                        h["holding"] = null
                        h["hold_ms"] = 0.0
                        h["sprite"] = _make_sprite(
                                "res://assets/sprites/hazards/trap_armed.png", cell, 62.0)
                HazardType.CHASM:
                        # apertura differita casuale: le voragini NON
                        # appaiono tutte nello stesso istante
                        h["state"] = ChasmState.DORMANT
                        h["timer_ms"] = float(_rng.randi_range(500, 6000))
                        h["sprite"] = null  # sprite creato al CRACK
                HazardType.BARREL:
                        _spawn_barrel(cell)
                        return
        hazard_list.append(h)


# --- TASK 31: barili esplosivi ----------------------------------------------

## Barile: oggetto piazzato a terra. Un PROIETTILE del player sulla sua
## cella accende la miccia (istantanea); l'esplosione uccide i nemici nel
## raggio, ferisce il player troppo vicino e innesca gli altri barili.
## stati: 0 = integro, 1 = in esplosione (fuse per la catena).
enum BarrelState { INTACT, FUSE }

func _spawn_barrel(cell: Vector2i) -> void:
        var h: Dictionary = {
                "type": HazardType.BARREL,
                "cell": cell,
                "state": BarrelState.INTACT,
                "timer_ms": 0.0,
        }
        h["sprite"] = _make_sprite(
                "res://assets/sprites/hazards/barrel.png", cell, 54.0)
        hazard_list.append(h)


func _spawn_rock_wall(cell: Vector2i, maze: Node) -> void:
        var ew_open: bool = not maze.is_wall(cell.x - 1, cell.y) \
                        and not maze.is_wall(cell.x + 1, cell.y)
        var h: Dictionary = {
                "type": HazardType.ROCK_WALL,
                "cell": cell,
                "axis": "h" if ew_open else "v",
                "phase": WallPhase.OPEN,
                # fase iniziale sfasata: i muri non battono all'unisono
                "phase_ms": float(_rng.randi_range(0, C.HAZARD_WALL_OPEN_MS)),
                "off_a": WALL_OPEN_OFF,
                "off_b": WALL_OPEN_OFF,
        }
        var tex := "res://assets/sprites/hazards/rock_slab.png"
        h["slab_a"] = _make_sprite(tex, cell, 0.0)  # scala sistemata sotto
        h["slab_b"] = _make_sprite(tex, cell, 0.0)
        # ogni meta' copre l'intera cella (64x64); per un passaggio
        # orizzontale scivolano da sopra/sotto (la B capovolta si incastra
        # nella A). Passaggio verticale: ruotate di 90 gradi.
        # FIX (divisione intera): TILE_SIZE e get_width() sono INT -> 64/226
        # faceva 0 e la scala collassava a 1e-5 (lastre invisibili). Cast a
        # float PRIMA della divisione.
        var s: float = float(C.TILE_SIZE) / float(h["slab_a"].texture.get_width())
        # TASK 50 (integrazione nei muri — bug utente "sembrano pezzi esterni
        # che si muovono sopra il muro"): le lastre PixelLab sono grigie
        # neutre e ora vengono TINTE col colore dei muri del livello, cosi'
        # sembrano un PEZZO DEL MURO stesso che scorre, non un blocco estraneo.
        # La tinta preserva la luminosita' (normalizzata sul canale massimo)
        # per non scurire la lastra.
        var wall_tint: Color = Color.WHITE
        if maze != null and "wall_color" in maze:
                var wc: Color = maze.wall_color
                var lum: float = maxf(wc.r, maxf(wc.g, wc.b))
                if lum > 0.04:
                        wall_tint = Color(
                                        clampf(wc.r / lum * 0.92 + 0.08, 0.0, 1.0),
                                        clampf(wc.g / lum * 0.92 + 0.08, 0.0, 1.0),
                                        clampf(wc.b / lum * 0.92 + 0.08, 0.0, 1.0))
        for key in ["slab_a", "slab_b"]:
                h[key].scale = Vector2(s, s)
                h[key].self_modulate = wall_tint
                if h["axis"] == "v":
                        h[key].rotation = PI / 2.0
        h["slab_b"].flip_v = true
        hazard_list.append(h)
        _apply_wall_offsets(h)
        # registrazione nel Maze: la cella e' un muro DINAMICO attualmente
        # APERTO (attraversabile). is_wall() da qui in poi consulta il
        # registro, non il tipo statico.
        maze.dynamic_walls[_wall_key(cell)] = false


func _wall_key(cell: Vector2i) -> String:
        return "%d,%d" % [cell.x, cell.y]


func _apply_wall_offsets(h: Dictionary) -> void:
        var center: Vector2 = _cell_center(h["cell"])
        var a: Sprite2D = h["slab_a"]
        var b: Sprite2D = h["slab_b"]
        if h["axis"] == "h":
                a.position = center + Vector2(0.0, -float(h["off_a"]))
                b.position = center + Vector2(0.0, float(h["off_b"]))
        else:
                a.position = center + Vector2(-float(h["off_a"]), 0.0)
                b.position = center + Vector2(float(h["off_b"]), 0.0)


# ===========================================================================
# TASK 88 — LAME-RUOTA (blade wheels)
# ===========================================================================
# Ruote-lama che pattinano sul pavimento: partono DA UN MURO del corridoio,
# viaggiano fino al muro opposto e rimbalzano avanti-indietro per tutto il
# livello. Tocco = 50% dell'energia max (il salto scavalca: pattern
# take_hazard_damage blockable). Grafica pixel-art (sheet 4 frame di
# rotazione, PixelLab) + scia di scorrimento a 2 afterimage + scintille al
# rimbalzo sul muro.

## Corridoi muro-muro (orizzontali e verticali) di celle EMPTY consecutive,
## lunghi almeno BLADE_MIN_RUN_CELLS, lontani da tunnel/spawn/item.
func _collect_blade_runs(maze: Node) -> Array[Dictionary]:
        var runs: Array[Dictionary] = []
        # corridoi orizzontali (lane = riga)
        for r in range(1, C.MAZE_ROWS - 1):
                var c := 1
                while c < C.MAZE_COLS - 1:
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                c += 1
                                continue
                        var c0 := c
                        while c < C.MAZE_COLS - 1 \
                                        and maze.get_cell_type(c, r) == C.CellType.EMPTY:
                                c += 1
                        var c1 := c - 1
                        if maze.is_wall(c0 - 1, r) and maze.is_wall(c1 + 1, r) \
                                        and (c1 - c0 + 1) >= C.BLADE_MIN_RUN_CELLS \
                                        and _blade_run_clean(maze, r, c0, c1, "h"):
                                runs.append({"axis": "h", "lane": r, "c0": c0, "c1": c1})
        # corridoi verticali (lane = colonna)
        for c in range(1, C.MAZE_COLS - 1):
                var r := 1
                while r < C.MAZE_ROWS - 1:
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                r += 1
                                continue
                        var r0 := r
                        while r < C.MAZE_ROWS - 1 \
                                        and maze.get_cell_type(c, r) == C.CellType.EMPTY:
                                r += 1
                        var r1 := r - 1
                        if maze.is_wall(c, r0 - 1) and maze.is_wall(c, r1 + 1) \
                                        and (r1 - r0 + 1) >= C.BLADE_MIN_RUN_CELLS \
                                        and _blade_run_clean(maze, c, r0, r1, "v"):
                                runs.append({"axis": "v", "lane": c, "c0": r0, "c1": r1})
        return runs


## Un corridoio e' "pulito" se nessuna delle sue celle e' vicina ai tunnel,
## vicino allo spawn del player (1,1) o occupata da un collectible a terra.
func _blade_run_clean(maze: Node, lane: int, i0: int, i1: int, axis: String) -> bool:
        for i in range(i0, i1 + 1):
                var c: int = i if axis == "h" else lane
                var r: int = lane if axis == "h" else i
                if _near_tunnel(c, r):
                        return false
                if max(absi(c - 1), absi(r - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                        return false
                if controller != null and not controller._collectible_cell_free(c, r):
                        return false
        return true


## Estrae un corridoio casuale (seed del livello) a distanza di corsia
## BLADE_MIN_LANE_GAP dalle lame gia' piazzate e senza celle occupate.
func _pop_blade_run(runs: Array[Dictionary], used: Array[Vector2i],
                lanes: Array[int]) -> Dictionary:
        var order: Array[int] = []
        for i in runs.size():
                order.append(i)
        for i in order.size():
                var j: int = _rng.randi_range(i, order.size() - 1)
                var tmp: int = order[i]
                order[i] = order[j]
                order[j] = tmp
        for idx in order:
                var run: Dictionary = runs[idx]
                var ok := true
                for l in lanes:
                        if absi(run["lane"] - l) < C.BLADE_MIN_LANE_GAP:
                                ok = false
                                break
                if ok:
                        for i in range(run["c0"], run["c1"] + 1):
                                var rc: Vector2i = Vector2i(i, run["lane"]) \
                                                if run["axis"] == "h" \
                                                else Vector2i(run["lane"], i)
                                for u in used:
                                        if rc == u:
                                                ok = false
                                                break
                                if not ok:
                                        break
                if ok:
                        return run
        return {}


func _spawn_blade(run: Dictionary) -> void:
        var axis: String = run["axis"]
        var lane: int = run["lane"]
        var lo_cell: int = run["c0"]
        var hi_cell: int = run["c1"]
        var pos: Vector2
        var lo: float
        var hi: float
        if axis == "h":
                pos = Vector2(0.0, float(lane) * C.TILE_SIZE
                                + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                lo = float(lo_cell) * C.TILE_SIZE + 32.0
                hi = float(hi_cell + 1) * C.TILE_SIZE - 32.0
        else:
                pos = Vector2(float(lane) * C.TILE_SIZE + C.TILE_SIZE / 2.0, 0.0)
                lo = float(lo_cell) * C.TILE_SIZE + C.UI_HEIGHT + 32.0
                hi = float(hi_cell + 1) * C.TILE_SIZE + C.UI_HEIGHT - 32.0
        # parte DA UN MURO (lato casuale) e viaggia verso l'opposto
        var from_lo: bool = _rng.randf() < 0.5
        var dir: float = 1.0 if from_lo else -1.0
        if axis == "h":
                pos.x = lo if from_lo else hi
        else:
                pos.y = lo if from_lo else hi
        var sprite := _make_blade_sprite()
        sprite.position = pos
        var trail_a := _make_blade_sprite()
        trail_a.modulate = Color(1.0, 0.86, 0.74, 0.38)
        var trail_b := _make_blade_sprite()
        trail_b.modulate = Color(1.0, 0.78, 0.64, 0.20)
        hazard_list.append({
                "type": HazardType.BLADE,
                "cell": Vector2i(lane if axis == "v" else lo_cell,
                                lo_cell if axis == "v" else lane),
                "axis": axis, "lane": lane, "c0": lo_cell, "c1": hi_cell,
                "pos": pos, "dir": dir, "lo": lo, "hi": hi,
                "sprite": sprite, "trail_a": trail_a, "trail_b": trail_b,
                "spin0": float(_rng.randi_range(0, 3)),
        })


func _make_blade_sprite() -> Sprite2D:
        var s := Sprite2D.new()
        s.texture = _blade_frame(0)
        s.scale = Vector2(56.0 / 64.0, 56.0 / 64.0)
        s.z_index = 0
        add_child(s)
        return s


## Frame di rotazione della lama: sheet pixel-art 256x64 (4 frame 64x64,
## PixelLab TASK 88) caricato via Image.load (pattern SpriteManager). Se
## l'asset manca: ruota procedurale disegnata su Image (fallback).
func _blade_frame(i: int) -> Texture2D:
        if _blade_frames.is_empty():
                _load_blade_frames()
        if _blade_frames.is_empty():
                return null
        return _blade_frames[i % _blade_frames.size()]


func _load_blade_frames() -> void:
        var sheet: Texture2D = null
        var path := "res://assets/sprites/hazards/blade_wheel_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        sheet = ImageTexture.create_from_image(img)
        if sheet == null:
                sheet = _make_blade_fallback_tex()
        if sheet == null:
                return
        var fw: float = float(sheet.get_width()) / 4.0
        var fh: float = float(sheet.get_height())
        for i in 4:
                var at := AtlasTexture.new()
                at.atlas = sheet
                at.region = Rect2(fw * float(i), 0.0, fw, fh)
                _blade_frames.append(at)


func _make_blade_fallback_tex() -> Texture2D:
        var img := Image.create(256, 64, false, Image.FORMAT_RGBA8)
        img.fill(Color(0.0, 0.0, 0.0, 0.0))
        for f in 4:
                var cx: float = 32.0 + float(f) * 64.0
                var rot: float = float(f) * TAU / 4.0
                # denti (12) sul bordo, ruotati di un quarto di giro per frame
                for k in 12:
                        var a: float = float(k) * TAU / 12.0 + rot
                        for rr in range(23, 30):
                                img.set_pixel(int(cx + cos(a) * float(rr)),
                                                int(32.0 + sin(a) * float(rr)),
                                                Color(0.80, 0.78, 0.74, 1.0))
                # disco in acciaio con bordo piu' chiaro
                for x in range(-23, 24):
                        for y in range(-23, 24):
                                var d: float = sqrt(float(x * x + y * y))
                                if d <= 23.0:
                                        var col := Color(0.55, 0.53, 0.50, 1.0)
                                        if d > 20.0:
                                                col = Color(0.63, 0.61, 0.57, 1.0)
                                        if d <= 7.0:
                                                col = Color(0.36, 0.35, 0.34, 1.0)
                                        img.set_pixel(int(cx) + x, int(32.0) + y, col)
                # mozzo scuro
                for x in range(-3, 4):
                        for y in range(-3, 4):
                                if x * x + y * y <= 9:
                                        img.set_pixel(int(cx) + x, int(32.0) + y,
                                                        Color(0.18, 0.17, 0.16, 1.0))
        return ImageTexture.create_from_image(img)


## Update della lama: pattinaggio muro-muro con rimbalzo (scintille +
## grind al contatto), frame di rotazione, scia di scorrimento (2
## afterimage dietro la direzione del moto) e collisione coi player
## grounded (il salto scavalca: take_hazard_damage blockable, 50%).
func _update_blade(h: Dictionary, delta_ms: float, players: Array) -> void:
        var dt: float = delta_ms / 1000.0
        var pos: Vector2 = h["pos"]
        var dir: float = h["dir"]
        var along: float = pos.x if h["axis"] == "h" else pos.y
        along += dir * C.BLADE_SPEED_PX_S * dt
        if along < h["lo"]:
                along = h["lo"] + (h["lo"] - along)
                dir = 1.0
                _blade_wall_hit(h)
        elif along > h["hi"]:
                along = h["hi"] - (along - h["hi"])
                dir = -1.0
                _blade_wall_hit(h)
        h["dir"] = dir
        if h["axis"] == "h":
                pos.x = along
        else:
                pos.y = along
        h["pos"] = pos
        # rotazione (frame dello sheet) + posizione sprite e scia
        var fi: int = int(_time * C.BLADE_SPIN_FPS + float(h["spin0"])) % 4
        var tex: Texture2D = _blade_frame(fi)
        if tex == null:
                return
        var s: Sprite2D = h["sprite"]
        if s != null and is_instance_valid(s):
                s.texture = tex
                s.position = pos
        var back: Vector2 = Vector2(-dir, 0.0) if h["axis"] == "h" \
                        else Vector2(0.0, -dir)
        var ta: Sprite2D = h.get("trail_a", null)
        if ta != null and is_instance_valid(ta):
                ta.texture = tex
                ta.position = pos + back * 15.0
        var tb: Sprite2D = h.get("trail_b", null)
        if tb != null and is_instance_valid(tb):
                tb.texture = tex
                tb.position = pos + back * 28.0
        # collisione: player grounded sulla corsia, entro il raggio di contatto
        # (distanza perpendicolare = corsia; distanza lungo il moto = contatto)
        for p in players:
                if not _player_grounded(p):
                        continue
                var d_perp: float = absf(p.position.y - pos.y) if h["axis"] == "h" \
                                else absf(p.position.x - pos.x)
                var d_along: float = absf(p.position.x - pos.x) if h["axis"] == "h" \
                                else absf(p.position.y - pos.y)
                if d_perp > 28.0:
                        continue
                if d_along > C.BLADE_TOUCH_PX:
                        continue
                p.take_hazard_damage(maxi(1, int(
                                float(p.max_energy) * C.BLADE_DAMAGE_PCT)))


## Rimbalzo sul muro: grind metallico + scintille (pattern sparks del
## player: nodo aggiunto al parent del controller).
func _blade_wall_hit(h: Dictionary) -> void:
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_GRIND)
        if EffectsManager:
                var sparks: Node2D = EffectsManager.spawn_sparks(h["pos"], 5)
                if sparks != null and get_parent() != null:
                        get_parent().add_child(sparks)


# ===========================================================================
# TASK 89 — BLOCCHI DI LANCE (spike traps)
# ===========================================================================
# Lance che escono dal pavimento: a riposo si vedono APPENA LE PUNTE
# (scale.y ~0.18), a momento casuale VIBRANO (jitter, avviso ~0.7s) e si
# ALZANO (scale.y -> 1.0, ~0.38s) infilzando chi e' sulla cella. Restano
# fuori SPEAR_HOLD_MS (5s), poi vibrano e rientrano. Danno 50% UNBLOCKABLE:
# il salto NON protegge (pattern braccia zombie) — il player deve attendere
# che ritornino giu'. Piazzate DOPO le lame: mai sulle corsie delle lame.

## Cella per un blocco di lance: pattern _pop_cell con in piu' l'esclusione
## delle corsie delle lame (riga/colonna).
func _pop_spear_cell(cells: Array[Vector2i], used: Array[Vector2i]) -> Vector2i:
        for _attempt in 24:
                if cells.is_empty():
                        break
                var idx: int = _rng.randi_range(0, cells.size() - 1)
                var cell: Vector2i = cells[idx]
                var ok := not blade_rows.has(cell.y) and not blade_cols.has(cell.x)
                if ok:
                        for u in used:
                                if absi(cell.x - u.x) + absi(cell.y - u.y) < C.HAZARD_MIN_GAP:
                                        ok = false
                                        break
                if ok:
                        cells.remove_at(idx)
                        return cell
                cells.remove_at(idx)
        return Vector2i(-1, -1)


func _spawn_spear(cell: Vector2i) -> void:
        var cc: Vector2 = _cell_center(cell)
        var sprite := Sprite2D.new()
        sprite.texture = _spear_frame(_rng.randi_range(0, 3))
        sprite.z_index = 0
        add_child(sprite)
        hazard_list.append({
                "type": HazardType.SPEAR,
                "cell": cell,
                "cc": cc,
                "state": SpearState.HIDDEN,
                "timer_ms": float(_rng.randi_range(
                                C.SPEAR_HIDDEN_MIN_MS, C.SPEAR_HIDDEN_MAX_MS)),
                "sprite": sprite,
        })
        _spear_set_scale(hazard_list[hazard_list.size() - 1], 0.18)


## Scala verticale della sprite con ancoraggio al fondo cella: le punte
## spuntano dal pavimento e le lance crescono verso l'alto.
func _spear_set_scale(h: Dictionary, sc: float) -> void:
        var s: Sprite2D = h["sprite"]
        var cc: Vector2 = h["cc"]
        s.scale = Vector2(0.95, sc)
        s.position = Vector2(cc.x, cc.y + 24.0 - 32.0 * sc)


## Varianti pixel-art del blocco di lance (sheet 4 frame 64x64, PixelLab
## TASK 89) caricate via Image.load; fallback procedurale se manca l'asset.
func _spear_frame(i: int) -> Texture2D:
        if _spear_frames.is_empty():
                _load_spear_frames()
        if _spear_frames.is_empty():
                return null
        return _spear_frames[i % _spear_frames.size()]


func _load_spear_frames() -> void:
        var sheet: Texture2D = null
        var path := "res://assets/sprites/hazards/spear_tips_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        sheet = ImageTexture.create_from_image(img)
        if sheet == null:
                sheet = _make_spear_fallback_tex()
        if sheet == null:
                return
        var fw: float = float(sheet.get_width()) / 4.0
        var fh: float = float(sheet.get_height())
        for i in 4:
                var at := AtlasTexture.new()
                at.atlas = sheet
                at.region = Rect2(fw * float(i), 0.0, fw, fh)
                _spear_frames.append(at)


func _make_spear_fallback_tex() -> Texture2D:
        var img := Image.create(256, 64, false, Image.FORMAT_RGBA8)
        img.fill(Color(0.0, 0.0, 0.0, 0.0))
        for f in 4:
                var bx: int = 10 + f * 64
                # 3 lance per variante: asta + punta triangolare
                for k in 3:
                        var x: int = bx + 12 + k * 16
                        # asta legno
                        for y in range(28, 60):
                                img.set_pixel(x, y, Color(0.55, 0.42, 0.28, 1.0))
                                img.set_pixel(x + 1, y, Color(0.45, 0.34, 0.22, 1.0))
                        # punta acciaio (triangolo)
                        for ty in range(10, 30):
                                var wdt: int = maxi(1, int(float(30 - ty) * 0.28))
                                for tx in range(-wdt, wdt + 1):
                                        img.set_pixel(x + tx, ty,
                                                        Color(0.78, 0.79, 0.82, 1.0))
                        img.set_pixel(x, 10, Color(0.92, 0.93, 0.95, 1.0))
        return ImageTexture.create_from_image(img)


## Update del blocco di lance: macchina a stati HIDDEN -> WARN (vibrazione)
## -> RISING -> UP (5s) -> RETRACT_WARN (vibrazione) -> RETRACTING -> HIDDEN
## (nuovo delay casuale). Danno 50% UNBLOCKABLE quando le lance sono
## sufficientemente fuori (il salto NON protegge: nessun check grounded).
func _update_spear(h: Dictionary, delta_ms: float, players: Array) -> void:
        h["timer_ms"] = float(h["timer_ms"]) - delta_ms
        var s: Sprite2D = h["sprite"]
        var state: int = h["state"]
        match state:
                SpearState.HIDDEN:
                        _spear_set_scale(h, 0.18)
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.WARN
                                h["timer_ms"] = C.SPEAR_WARN_MS
                SpearState.WARN:
                        # vibrazione delle punte (jitter orizzontale + pulsazione)
                        _spear_set_scale(h, 0.24 + 0.02 * sin(float(h["timer_ms"]) * 0.08))
                        s.position.x = (h["cc"] as Vector2).x + randf_range(-2.4, 2.4)
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.RISING
                                h["timer_ms"] = C.SPEAR_RISE_MS
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.HAZARD_SNAP)
                SpearState.RISING:
                        var k: float = 1.0 - clampf(float(h["timer_ms"])
                                        / C.SPEAR_RISE_MS, 0.0, 1.0)
                        _spear_set_scale(h, lerpf(0.24, 1.0, k))
                        s.position.x = (h["cc"] as Vector2).x
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.UP
                                h["timer_ms"] = C.SPEAR_HOLD_MS
                SpearState.UP:
                        _spear_set_scale(h, 1.0)
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.RETRACT_WARN
                                h["timer_ms"] = C.SPEAR_RETRACT_WARN_MS
                SpearState.RETRACT_WARN:
                        s.position.x = (h["cc"] as Vector2).x + randf_range(-2.0, 2.0)
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.RETRACTING
                                h["timer_ms"] = C.SPEAR_RETRACT_MS
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.HAZARD_THUD)
                SpearState.RETRACTING:
                        var k2: float = clampf(float(h["timer_ms"])
                                        / C.SPEAR_RETRACT_MS, 0.0, 1.0)
                        _spear_set_scale(h, lerpf(0.24, 1.0, k2))
                        s.position.x = (h["cc"] as Vector2).x
                        if h["timer_ms"] <= 0.0:
                                h["state"] = SpearState.HIDDEN
                                h["timer_ms"] = float(_rng.randi_range(
                                                C.SPEAR_HIDDEN_MIN_MS,
                                                C.SPEAR_HIDDEN_MAX_MS))
        # danno: lance abbastanza fuori (emersione oltre meta', fuori pieno,
        # vibrazione pre-rientro, rientro oltre meta') — UNBLOCKABLE: il
        # salto NON protegge, il player deve attendere che rientrino.
        var armed: bool = state == SpearState.UP or state == SpearState.RETRACT_WARN
        if state == SpearState.RISING and float(h["timer_ms"]) < C.SPEAR_RISE_MS * 0.5:
                armed = true
        if state == SpearState.RETRACTING and float(h["timer_ms"]) < C.SPEAR_RETRACT_MS * 0.4:
                armed = true
        if armed:
                for p in players:
                        if _player_cell(p) != h["cell"]:
                                continue
                        p.take_hazard_damage(maxi(1, int(
                                        float(p.max_energy) * C.SPEAR_DAMAGE_PCT)), true)


# ===========================================================================
# UPDATE
# ===========================================================================

## Chiamato da MainGameController._update_playing DOPO l'update dei player
## e PRIMA di quello dei nemici: le celle occupate sono fresche, i flag
## held_by_wall sono gia' validi per il movimento nemico del frame stesso.
func update_hazards(delta_ms: float, maze: Node) -> void:
        if not C.HAZARDS_ENABLED and not C.BARRELS_ENABLED and not C.QUAKE_ENABLED:
                _reset_players_flags()
                return
        _time += delta_ms / 1000.0
        var players: Array = _active_players()

        for h in hazard_list:
                match h["type"]:
                        HazardType.QUICKSAND:
                                _update_quicksand(h)
                        HazardType.TRAP:
                                _update_trap(h, delta_ms, players, maze)
                        HazardType.CHASM:
                                _update_chasm(h, delta_ms, players, maze)
                        HazardType.ROCK_WALL:
                                _update_rock_wall(h, delta_ms, maze)
                        HazardType.BARREL:
                                _update_barrel(h, delta_ms, players)
                        HazardType.BLADE:
                                _update_blade(h, delta_ms, players)
                        HazardType.SPEAR:
                                _update_spear(h, delta_ms, players)

        # Mjolnir: se la cella muro non e' piu' WALL (spezzata), il muro di
        # roccia si sgretola e despawna.
        for i in range(hazard_list.size() - 1, -1, -1):
                var h: Dictionary = hazard_list[i]
                if h["type"] == HazardType.ROCK_WALL \
                                and maze.get_cell_type(h["cell"].x, h["cell"].y) != C.CellType.WALL:
                        _poof_wall(h)
                        hazard_list.remove_at(i)

        _update_players_slow(players, maze)
        _update_quake(delta_ms, maze, players)
        _update_scroll_chasms(delta_ms)


# ===========================================================================
# TASK 35 — VORAGINI MAGICHE della pergamena
# ===========================================================================

## Attiva l'effetto della PERGAMENA DELLE VORAGINI: 3 ondate da 4 voragini
## ciascuna. `owner` e' il player che ha raccolto la pergamena (a lui vanno
## i punti delle uccisioni). Chiamato dal MainGameController alla raccolta.
func start_scroll_chasms(owner: CharacterBody2D) -> void:
        scroll_chasm_owner = owner
        scroll_chasm_waves_left = C.SCROLL_CHASM_WAVES
        _spawn_scroll_wave()


## Piazza un'ondata di 4 voragini in celle EMPTY casuali BEN DISTANZIATE
## tra loro (Manhattan >= SCROLL_CHASM_MIN_GAP) e non occupate da item a
## terra. Le celle NON vanno in dynamic_walls: il pathing dei nemici non
## le vede (e' il punto: devono CRISCADERCI dentro).
func _spawn_scroll_wave() -> void:
        # Celle EMPTY valide: non tunnel, non occupate da item a terra
        # (il maze arriva dal controller, che possiede il riferimento).
        var valid: Array[Vector2i] = []
        if controller != null and controller.maze != null:
                for r in range(1, C.MAZE_ROWS - 1):
                        for c in range(1, C.MAZE_COLS - 1):
                                if controller.maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                        continue
                                if _near_tunnel(c, r):
                                        continue
                                if not controller._collectible_cell_free(c, r):
                                        continue
                                valid.append(Vector2i(c, r))
        var placed: Array[Vector2i] = []
        for _i in C.SCROLL_CHASM_COUNT:
                var cell := _pop_far_cell(valid, placed, C.SCROLL_CHASM_MIN_GAP)
                if cell == Vector2i(-1, -1):
                        break
                placed.append(cell)
                var s := _make_sprite(
                        "res://assets/sprites/hazards/chasm_open.png", cell, 66.0)
                # tinta magica VIOLA: si distinguono dalle voragini normali
                s.modulate = Color(0.82, 0.62, 1.0)
                s.modulate.a = 0.0  # fade-in rapido
                scroll_chasm_list.append({
                        "cell": cell,
                        "sprite": s,
                        "state": 0,  # 0 = OPEN
                        "timer_ms": float(C.SCROLL_CHASM_WAVE_MS),
                })
        if AudioManager and not placed.is_empty():
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_COLLAPSE)
                AudioManager.play_sound(AudioManager.SoundType.PORTAL_OPEN)
        if EffectsManager and not placed.is_empty():
                EffectsManager.screen_shake(4.0, 0.3)


## Estrae una cella casuale a distanza Manhattan >= min_gap da tutte le
## celle gia' piazzate (fallback: la prima disponibile se il vincolo non
## e' soddisfacibile in un labirinto piccolo).
func _pop_far_cell(cells: Array[Vector2i], placed: Array[Vector2i],
                min_gap: int) -> Vector2i:
        for _attempt in 30:
                if cells.is_empty():
                        break
                var idx: int = _rng.randi_range(0, cells.size() - 1)
                var cell: Vector2i = cells[idx]
                var ok := true
                for u in placed:
                        if absi(cell.x - u.x) + absi(cell.y - u.y) < min_gap:
                                ok = false
                                break
                cells.remove_at(idx)
                if ok:
                        return cell
        if cells.size() > 0:
                return cells.pop_back()
        return Vector2i(-1, -1)


## Update delle voragini magiche: fade-in, uccisione dei nemici che vi
## entrano, dissolvenza a fine ondata e riposizionamento (nuova ondata).
func _update_scroll_chasms(delta_ms: float) -> void:
        if scroll_chasm_list.is_empty() and scroll_chasm_waves_left <= 0:
                return
        for i in range(scroll_chasm_list.size() - 1, -1, -1):
                var h: Dictionary = scroll_chasm_list[i]
                h["timer_ms"] -= delta_ms
                match h["state"]:
                        0:  # OPEN: fade-in rapido + caccia ai nemici
                                var s: Sprite2D = h["sprite"]
                                if is_instance_valid(s):
                                        s.modulate.a = minf(1.0,
                                                        s.modulate.a + delta_ms / 300.0)
                                _kill_enemies_on_chasm(h)
                                if h["timer_ms"] <= 0.0:
                                        h["state"] = 1
                                        h["timer_ms"] = float(C.SCROLL_CHASM_FADE_MS)
                        1:  # FADE: dissolvenza, niente piu' uccisioni
                                var sf: Sprite2D = h["sprite"]
                                if is_instance_valid(sf):
                                        sf.modulate.a = maxf(0.0,
                                                        sf.modulate.a - delta_ms / float(C.SCROLL_CHASM_FADE_MS))
                                if h["timer_ms"] <= 0.0:
                                        if is_instance_valid(sf):
                                                sf.queue_free()
                                        scroll_chasm_list.remove_at(i)
        # fine ondata: se restano ondate, riposiziona subito le voragini
        if scroll_chasm_list.is_empty() and scroll_chasm_waves_left > 0:
                scroll_chasm_waves_left -= 1
                if scroll_chasm_waves_left > 0:
                        _spawn_scroll_wave()
                else:
                        scroll_chasm_owner = null
                        if AudioManager:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.PORTAL_CLOSE)


## Uccide ogni nemico vivo che si trova sulla cella di una voragine
## magica (+ punti al raccoglitore della pergamena). Il PLAYER non e'
## MAI controllato: la richiesta utente e' che non possa caderci.
func _kill_enemies_on_chasm(h: Dictionary) -> void:
        if controller == null:
                return
        for e in controller.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                var ecell := Vector2i(
                                int(e.position.x / C.TILE_SIZE),
                                int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                if ecell != h["cell"]:
                        continue
                e.take_damage(99999)
                if e.is_dead() and scroll_chasm_owner != null:
                        scroll_chasm_owner.add_score(C.SCROLL_CHASM_KILL_POINTS)
                if e.is_dead():
                        if AudioManager:
                                AudioManager.play_sound(
                                                AudioManager.SoundType.ENEMY_DEATH)
                        if EffectsManager:
                                var dust := EffectsManager.spawn_explosion(
                                                e.position, Color(0.5, 0.35, 0.7), 12, 0.5)
                                controller.collectibles_node.add_child(dust)
        # mini-boss sulla voragine: stessa regola (kill + 10000)
        var mb = controller.mini_boss
        if mb != null and is_instance_valid(mb) and not mb.is_dead():
                var mb_cell := Vector2i(
                                int(mb.position.x / C.TILE_SIZE),
                                int((mb.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                if mb_cell == h["cell"]:
                        mb.take_damage(99999)
                        if mb.is_dead():
                                if scroll_chasm_owner != null:
                                        scroll_chasm_owner.add_score(
                                                        C.HAZARD_WALL_KILL_POINTS)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                        AudioManager.SoundType.BOSS_DEATH)


## Rimuove tutte le voragini della pergamena (clear a fine livello).
func _clear_scroll_chasms() -> void:
        for h in scroll_chasm_list:
                if is_instance_valid(h.get("sprite")):
                        h["sprite"].queue_free()
        scroll_chasm_list.clear()
        scroll_chasm_waves_left = 0
        scroll_chasm_owner = null


## Celle delle voragini attive (per test/debug).
func scroll_chasm_cells() -> Array[Vector2i]:
        var out: Array[Vector2i] = []
        for h in scroll_chasm_list:
                out.append(h["cell"])
        return out


func _reset_players_flags() -> void:
        if controller == null:
                return
        for p in _active_players():
                p.hazard_slow = 1.0
                p.held_by_wall = false
                if p.held_by_trap and not _trap_holding(p):
                        p.held_by_trap = false


func _trap_holding(_p: CharacterBody2D) -> bool:
        for h in hazard_list:
                if h["type"] == HazardType.TRAP and h.get("holding") == _p:
                        return true
        return false


func _active_players() -> Array:
        var out: Array = []
        if controller == null:
                return out
        var p1: CharacterBody2D = controller.player
        if p1 != null and p1.visible and not p1.soul_pending:
                out.append(p1)
        if controller.player2 != null and controller.player2.visible \
                        and not controller.player2.soul_pending:
                out.append(controller.player2)
        return out


func _player_cell(p: CharacterBody2D) -> Vector2i:
        return Vector2i(
                int(p.position.x / C.TILE_SIZE),
                int((p.position.y - C.UI_HEIGHT) / C.TILE_SIZE))


## Un player e' "grounded" sulla cella se NON sta saltando (il salto e'
## l'arco che copre l'intera cella: pattern "salto sopra le armi").
func _player_grounded(p: CharacterBody2D) -> bool:
        return not p.is_jumping() and not p.is_ghost()


# --- quicksand --------------------------------------------------------------

func _update_quicksand(h: Dictionary) -> void:
        # vortice lento: rotazione continua + respiro di scala
        var s: Sprite2D = h["sprite"]
        s.rotation += 0.25 * (_time - float(h.get("last_t", 0.0)))
        h["last_t"] = _time
        var k: float = 1.0 + 0.04 * sin(_time * 2.0)
        s.scale = Vector2(66.0 / s.texture.get_width(), 66.0 / s.texture.get_height()) * k


func _update_players_slow(players: Array, maze: Node) -> void:
        for p in players:
                var slow: float = 1.0
                if p.held_by_trap or p.held_by_wall:
                        slow = 1.0
                elif not p.is_ghost() and not p.is_jumping():
                        var cell := _player_cell(p)
                        for h in hazard_list:
                                if h["type"] == HazardType.QUICKSAND \
                                                and h["cell"] == cell:
                                        # STIVALI ALATI (speed boots): chi vola
                                        # non affonda — il malus e' annullato.
                                        if p.permanent_speed_boost:
                                                slow = 1.0
                                        else:
                                                slow = C.HAZARD_QUICKSAND_SLOW
                                        break
                p.hazard_slow = slow


# --- trap -------------------------------------------------------------------

func _update_trap(h: Dictionary, delta_ms: float, players: Array, _maze: Node) -> void:
        match h["state"]:
                TrapState.ARMED:
                        # disarmo: proiettile di qualunque player nella cella
                        # (TASK 34: scatto a vuoto = disattivazione permanente)
                        if _projectile_in_cell(h["cell"], players):
                                _snap_trap(h, null, false)
                                return
                        # cattura: player grounded nella cella
                        for p in players:
                                if _player_grounded(p) \
                                                and _player_cell(p) == h["cell"] \
                                                and not p.held_by_trap:
                                        _snap_trap(h, p, true)
                                        return
                TrapState.SNAPPED:
                        var victim: CharacterBody2D = h["holding"]
                        if victim != null:
                                # morte/teletrasporto della vittima: libera
                                if not is_instance_valid(victim) \
                                                or not victim.visible \
                                                or _player_cell(victim) != h["cell"]:
                                        _release_trap(h)
                                        return
                                # mash: ogni pressione consumata accorcia
                                var mash: int = victim.input_mash_count
                                if mash > 0:
                                        victim.input_mash_count = 0
                                        h["hold_ms"] = maxf(
                                                C.HAZARD_TRAP_HOLD_MIN_MS,
                                                h["hold_ms"] - C.HAZARD_TRAP_MASH_REDUCE_MS * mash)
                                # tieni il player agganciato al centro
                                var center: Vector2 = _cell_center(h["cell"])
                                victim.position = victim.position.move_toward(
                                        center, 3.0 * delta_ms / 16.6667)
                                victim.held_by_trap = true
                                h["hold_ms"] -= delta_ms
                                if h["hold_ms"] <= 0.0:
                                        _release_trap(h)
                        else:
                            # scatto a vuoto (disarmo): la ganascia resta
                            # SPRUNG (gestito in _snap_trap)
                            pass
                TrapState.SPRUNG:
                        # TASK 34: scattata = DISATTIVATA per tutto il livello.
                        # Nessun riarmo: il player che ci passa sopra e' al
                        # sicuro (l'ha gia' colpito una volta, o e' stata
                        # bonificata con un colpo).
                        pass
        # NOTA: il parametro maze non e' usato qui (le ganasce non toccano
        # i muri), resta nella firma per simmetria con gli altri update.


func _snap_trap(h: Dictionary, victim: CharacterBody2D, with_player: bool) -> void:
        if AudioManager:
                if with_player:
                        AudioManager.play_sound(AudioManager.SoundType.HAZARD_SNAP)
                else:
                        AudioManager.play_sound(AudioManager.SoundType.HAZARD_DISARM)
        _set_trap_sprite(h, false)
        if with_player and victim != null:
                h["state"] = TrapState.SNAPPED
                h["holding"] = victim
                h["hold_ms"] = float(C.HAZARD_TRAP_HOLD_MS)
                victim.held_by_trap = true
                victim.dx = 0
                victim.dy = 0
                # danno ambientale: 33% energia max, BYPASS armature
                var dmg: int = maxi(1, int(round(
                        victim.max_energy * C.HAZARD_TRAP_DAMAGE_PCT)))
                victim.take_hazard_damage(dmg)
                if EffectsManager:
                        EffectsManager.screen_shake(5.0, 0.3)
                        var sp := EffectsManager.spawn_sparks(_cell_center(h["cell"]), 10)
                        if controller != null:
                                controller.collectibles_node.add_child(sp)
                # se il danno ha ucciso, il player e' gia' respawnato allo
                # spawn: la trap si libera al prossimo giro (_player_cell != cell)
        else:
                # TASK 34: scatto a vuoto (proiettile) = DISATTIVATA per
                # sempre: niente piu' riarmo.
                h["state"] = TrapState.SPRUNG
                h["holding"] = null


func _release_trap(h: Dictionary) -> void:
        var victim: CharacterBody2D = h["holding"]
        if victim != null and is_instance_valid(victim):
                victim.held_by_trap = false
        h["holding"] = null
        # TASK 34: fine della tenuta = DISATTIVATA (il player e' stato
        # colpito, questa ganascia non colpira' mai piu' nessuno).
        h["state"] = TrapState.SPRUNG


func _set_trap_sprite(h: Dictionary, armed: bool) -> void:
        var path: String = "res://assets/sprites/hazards/trap_armed.png" if armed \
                        else "res://assets/sprites/hazards/trap_closed.png"
        if h["sprite"] == null:
                h["sprite"] = _make_sprite(path, h["cell"], 62.0)
        else:
                h["sprite"].texture = _tex(path)


func _projectile_in_cell(cell: Vector2i, players: Array) -> bool:
        for p in players:
                for proj in p.projectiles:
                        if not proj.get("active", false):
                                continue
                        var pos: Vector2 = proj["pos"]
                        if int(pos.x / C.TILE_SIZE) == cell.x \
                                        and int((pos.y - C.UI_HEIGHT) / C.TILE_SIZE) == cell.y:
                                proj["active"] = false  # il colpo "consuma" la ganascia
                                return true
        return false


# --- chasm ------------------------------------------------------------------

func _update_chasm(h: Dictionary, delta_ms: float, players: Array, _maze: Node) -> void:
        match h["state"]:
                ChasmState.DORMANT:
                        h["timer_ms"] -= delta_ms
                        if h["timer_ms"] <= 0.0:
                                h["state"] = ChasmState.CRACK
                                h["timer_ms"] = float(C.HAZARD_CHASM_TELEGRAPH_MS)
                                h["sprite"] = _make_sprite(
                                        "res://assets/sprites/hazards/chasm_crack.png",
                                        h["cell"], 64.0)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_RUMBLE)
                                if EffectsManager:
                                        EffectsManager.screen_shake(2.0, 0.35)
                ChasmState.CRACK:
                        h["timer_ms"] -= delta_ms
                        # lampeggio d'allerta della crepa
                        if h["sprite"] != null:
                                h["sprite"].modulate.a = 0.75 + 0.25 * sin(_time * 18.0)
                        if h["timer_ms"] <= 0.0:
                                _open_chasm(h, _maze)
                ChasmState.OPEN:
                        # chi cammina (grounded) nella cella aperta cade
                        for p in players:
                                if _player_grounded(p) \
                                                and _player_cell(p) == h["cell"]:
                                        p.fall_into_chasm()
                                        return


func _open_chasm(h: Dictionary, _maze: Node) -> void:
        h["state"] = ChasmState.OPEN
        if h["sprite"] != null:
                h["sprite"].queue_free()
        h["sprite"] = _make_sprite(
                "res://assets/sprites/hazards/chasm_open.png", h["cell"], 66.0)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_COLLAPSE)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.4)
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(h["cell"]), Color(0.35, 0.3, 0.25), 14, 0.5)
                if controller != null:
                        controller.collectibles_node.add_child(dust)


# --- rock wall --------------------------------------------------------------

func _update_rock_wall(h: Dictionary, delta_ms: float, maze: Node) -> void:
        h["phase_ms"] += delta_ms
        match h["phase"]:
                WallPhase.OPEN:
                        if h["phase_ms"] >= float(C.HAZARD_WALL_OPEN_MS):
                                h["phase"] = WallPhase.WARN
                                h["phase_ms"] = 0.0
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)
                WallPhase.WARN:
                        # vibrazione pre-chiusura: le rocce strisciano verso
                        # il centro con jitter (telegrafo)
                        if h["phase_ms"] >= float(C.HAZARD_WALL_WARN_MS):
                                h["phase"] = WallPhase.CLOSED
                                h["phase_ms"] = 0.0
                                _close_wall(h, maze)
                WallPhase.CLOSED:
                        if h["phase_ms"] >= float(C.HAZARD_WALL_CLOSED_MS):
                                h["phase"] = WallPhase.OPEN
                                h["phase_ms"] = 0.0
                                maze.dynamic_walls[_wall_key(h["cell"])] = false
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)

        # inseguimento del target di offset (slam/apertura animati)
        var target: float = WALL_CLOSED_OFF if h["phase"] == WallPhase.CLOSED \
                        else WALL_OPEN_OFF
        var step: float = WALL_SLAM_SPEED * delta_ms / 1000.0
        h["off_a"] = move_toward(float(h["off_a"]), target, step)
        h["off_b"] = move_toward(float(h["off_b"]), target, step)
        # vibrazione durante il WARN
        var jitter := 0.0
        if h["phase"] == WallPhase.WARN:
                jitter = sin(_time * 60.0) * WALL_JITTER
        var save_a: float = h["off_a"]
        var save_b: float = h["off_b"]
        h["off_a"] += jitter
        h["off_b"] -= jitter
        _apply_wall_offsets(h)
        h["off_a"] = save_a
        h["off_b"] = save_b

        # flag held per player/nemici nella cella CHUSA (ricalcolo per-frame:
        # niente flag che restano appiccicati dopo respawn/morte)
        if h["phase"] == WallPhase.CLOSED:
                _hold_entities_in_wall(h, maze)
        else:
                _release_entities_in_wall(h, maze)


func _close_wall(h: Dictionary, maze: Node) -> void:
        var cell: Vector2i = h["cell"]
        maze.dynamic_walls[_wall_key(cell)] = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_THUD)
        # TASK 51 (richiesta utente): RIMOSSO lo screen shake alla chiusura —
        # con piu' muri che si aprono/chiudono lo schermo vibrava di
        # continuo e risultava fastidioso. Restano thud + polvere locale.
        if EffectsManager:
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(cell), Color(0.4, 0.35, 0.3), 18, 0.6)
                if controller != null:
                        controller.collectibles_node.add_child(dust)

        # player nella cella alla chiusura: danno 66% (se non airborne) e
        # imprigionamento fino alla riapertura. GHOST: il fantasma fluttua
        # sopra tutto (spec Task 30) — niente danno, niente tenuta.
        for p in _active_players():
                if _player_cell(p) == cell and not p.is_ghost():
                        p.held_by_wall = true
                        var dmg: int = maxi(1, int(round(
                                p.max_energy * C.HAZARD_WALL_PLAYER_DAMAGE_PCT)))
                        p.take_hazard_damage(dmg)

        # nemici nella cella: 33% HP max, bloccati finche' chiuso; ucciso
        # dal muro = 2x punti al player vivo piu' vicino
        if controller == null:
                return
        for e in controller.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                var ecell := Vector2i(
                        int(e.position.x / C.TILE_SIZE),
                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                if ecell != cell:
                        continue
                var dmg: int = maxi(1, int(round(
                        e.get_max_health() * C.HAZARD_WALL_ENEMY_DAMAGE_PCT)))
                e.take_damage(dmg)
                if e.is_dead():
                        var winner := _nearest_player(e.position)
                        if winner != null:
                                winner.add_score(C.HAZARD_WALL_KILL_POINTS)
                        if EffectsManager:
                                var blood := EffectsManager.spawn_blood(
                                        e.position, 18)
                                controller.collectibles_node.add_child(blood)
                else:
                        e.held_by_wall = true


func _hold_entities_in_wall(h: Dictionary, _maze: Node) -> void:
        var cell: Vector2i = h["cell"]
        for p in _active_players():
                if _player_cell(p) == cell:
                        # TASK 51 (richiesta utente): pozione fantasma / salto =
                        # il player VOLA sopra i muri che si aprono/chiudono:
                        # mai imprigionato (e libero se era tenuto). Con la
                        # pozione si attraversa il muro CHIUSO senza bloccarsi.
                        if p.is_ghost() or p.is_jumping():
                                p.held_by_wall = false
                                continue
                        p.held_by_wall = true
        if controller != null:
                for e in controller.spawner.enemies:
                        if e != null and is_instance_valid(e) and not e.is_dead():
                                var ecell := Vector2i(
                                        int(e.position.x / C.TILE_SIZE),
                                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                if ecell == cell:
                                        e.held_by_wall = true


func _release_entities_in_wall(h: Dictionary, _maze: Node) -> void:
        # il rilascio e' per-cellula: libera SOLO chi e' nella cella di
        # QUESTO muro (altri muri chiusi devono continuare a tenere)
        var cell: Vector2i = h["cell"]
        for p in _active_players():
                if p.held_by_wall and _player_cell(p) == cell:
                        p.held_by_wall = false
        if controller != null:
                for e in controller.spawner.enemies:
                        if e != null and is_instance_valid(e) \
                                        and e.held_by_wall:
                                var ecell := Vector2i(
                                        int(e.position.x / C.TILE_SIZE),
                                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                if ecell == cell:
                                        e.held_by_wall = false


func _nearest_player(from_pos: Vector2) -> CharacterBody2D:
        var best: CharacterBody2D = null
        var best_d: float = INF
        for p in _active_players():
                var d: float = p.position.distance_squared_to(from_pos)
                if d < best_d:
                        best_d = d
                        best = p
        return best


func _poof_wall(h: Dictionary) -> void:
        if is_instance_valid(h.get("slab_a")):
                h["slab_a"].queue_free()
        if is_instance_valid(h.get("slab_b")):
                h["slab_b"].queue_free()
        if EffectsManager and controller != null:
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(h["cell"]), Color(0.4, 0.35, 0.3), 14, 0.5)
                controller.collectibles_node.add_child(dust)


# ===========================================================================
# TASK 31 — BARILI: update + esplosione
# ===========================================================================

func _update_barrel(h: Dictionary, delta_ms: float, players: Array) -> void:
        match h["state"]:
                BarrelState.INTACT:
                        # un proiettile del player sulla cella accende la
                        # miccia (il colpo viene consumato)
                        if _projectile_in_cell(h["cell"], players):
                                _explode_barrel(h)
                BarrelState.FUSE:
                        # reazione a catena: brevissimo fuse poi boom
                        h["timer_ms"] -= delta_ms
                        # lampeggio di avviso mentre la miccia brucia
                        if h["sprite"] != null:
                                h["sprite"].modulate.r = 1.0 \
                                                + 0.6 * sin(_time * 40.0)
                        if h["timer_ms"] <= 0.0:
                                _explode_barrel(h)


func _explode_barrel(h: Dictionary) -> void:
        var center: Vector2 = _cell_center(h["cell"])
        # rimuovi subito il barile (niente doppie esplosioni)
        var idx: int = hazard_list.find(h)
        if idx >= 0:
                hazard_list.remove_at(idx)
        if is_instance_valid(h.get("sprite")):
                h["sprite"].queue_free()
        # VFX + SFX
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.BARREL_EXPLODE)
        if EffectsManager:
                EffectsManager.screen_shake(9.0, 0.45)
                var boom := EffectsManager.spawn_explosion(
                        center, Color(1.0, 0.55, 0.15), 34, 0.7)
                var smoke := EffectsManager.spawn_explosion(
                        center + Vector2(0.0, -10.0), Color(0.25, 0.22, 0.2), 16, 1.0)
                if controller != null:
                        controller.collectibles_node.add_child(boom)
                        controller.collectibles_node.add_child(smoke)
        # nemici nel raggio: uccisione istantanea (come la mina) + punti
        # standard al player vivo piu' vicino
        if controller != null:
                for e in controller.spawner.enemies:
                        if e == null or not is_instance_valid(e) or e.is_dead():
                                continue
                        if e.position.distance_to(center) <= C.BARREL_EXPLOSION_RADIUS:
                                e.take_damage(99999)
                                if e.is_dead():
                                        var winner := _nearest_player(e.position)
                                        if winner != null:
                                                winner.add_score(C.BARREL_KILL_POINTS)
                                        if EffectsManager:
                                                var blood := EffectsManager.spawn_blood(
                                                        e.position, 14)
                                                controller.collectibles_node.add_child(blood)
        # player nel raggio (grounded): danno ambientale 33% energia max —
        # saltare al momento giusto salva (skill!)
        for p in _active_players():
                if p.is_ghost() or p.is_jumping():
                        continue
                if p.position.distance_to(center) <= C.BARREL_EXPLOSION_RADIUS:
                        var dmg: int = maxi(1, int(round(
                                p.max_energy * C.BARREL_PLAYER_DAMAGE_PCT)))
                        p.take_hazard_damage(dmg)
        # TASK 34 (richiesta utente): l'esplosione del barile ELIMINA anche
        # la nube di pipistrelli se e' nel raggio (esplosione = dispersione
        # istantanea dello sciame, punti al player vivo piu' vicino).
        if controller != null and controller.bat_cloud != null \
                        and is_instance_valid(controller.bat_cloud):
                if controller.bat_cloud.position.distance_to(center) \
                                <= C.BARREL_EXPLOSION_RADIUS:
                        var scorer: CharacterBody2D = _nearest_player(
                                        controller.bat_cloud.position)
                        if scorer == null:
                                scorer = controller.player
                        controller.bat_cloud.take_explosion_hit(scorer)
        # reazione a catena: gli altri barili nel raggio accendono la miccia
        for other in hazard_list:
                if other["type"] == HazardType.BARREL \
                                and other["state"] == BarrelState.INTACT \
                                and _cell_center(other["cell"]).distance_to(center) \
                                                <= C.BARREL_EXPLOSION_RADIUS:
                        other["state"] = BarrelState.FUSE
                        other["timer_ms"] = float(C.BARREL_CHAIN_DELAY_MS)


# ===========================================================================
# TASK 31 — TERREMOTO: macchina a stati + massi
# ===========================================================================

func _update_quake(delta_ms: float, maze: Node, players: Array) -> void:
        if quake_events_left <= 0 and quake_state == QuakeState.INACTIVE:
                return
        match quake_state:
                QuakeState.INACTIVE:
                        quake_timer_ms -= delta_ms
                        if quake_timer_ms <= 0.0:
                                quake_state = QuakeState.TELEGRAPH
                                quake_timer_ms = float(C.QUAKE_TELEGRAPH_MS)
                                quake_shake_accum = 0.0
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_RUMBLE)
                QuakeState.TELEGRAPH:
                        # scrollamento continuo per tutta la durata del rombo
                        quake_timer_ms -= delta_ms
                        quake_shake_accum += delta_ms
                        if quake_shake_accum >= 280.0 and EffectsManager:
                                EffectsManager.screen_shake(3.0, 0.22)
                                quake_shake_accum = 0.0
                        if quake_timer_ms <= 0.0:
                                _quake_start_dropping(maze)
                QuakeState.DROPPING:
                        # i massi vivono in boulder_list; l'evento finisce
                        # quando sono caduti (o svaniti) tutti
                        if boulder_list.is_empty():
                                quake_state = QuakeState.INACTIVE
                                quake_events_left -= 1
                                if quake_events_left > 0:
                                        # secondo evento del livello (20+)
                                        quake_timer_ms = float(_rng.randi_range(
                                                        15000, 25000))
        # update dei singoli massi (mark -> fall -> rubble)
        for i in range(boulder_list.size() - 1, -1, -1):
                var b: Dictionary = boulder_list[i]
                _update_boulder(b, delta_ms, players)
                if b.get("done", false):
                        boulder_list.remove_at(i)


## Sceglie le celle bersaglio dei massi e crea i marker (crepa pulsante).
func _quake_start_dropping(maze: Node) -> void:
        quake_state = QuakeState.DROPPING
        var n: int = C.quake_boulder_count(quake_level)
        var cells: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        # niente massi addosso allo spawn (grace 2 celle)
                        if max(absi(c - 1), absi(r - 1)) < 2:
                                continue
                        cells.append(Vector2i(c, r))
        for _i in n:
                if cells.is_empty():
                        break
                var idx: int = _rng.randi_range(0, cells.size() - 1)
                var cell: Vector2i = cells[idx]
                cells.remove_at(idx)
                var b: Dictionary = {
                        "cell": cell,
                        "state": 0,  # 0 = MARK (crepa), 1 = FALL
                        "timer_ms": float(C.QUAKE_MARK_MS),
                        # scaglione: i massi non cadono tutti insieme
                        "delay_ms": float(_rng.randi_range(0, 1200)),
                        "sprite": _make_sprite(
                                "res://assets/sprites/hazards/chasm_crack.png",
                                cell, 58.0),
                        "fall_sprite": null,
                }
                b["sprite"].modulate = Color(1.0, 0.85, 0.7, 0.9)
                boulder_list.append(b)


func _update_boulder(b: Dictionary, delta_ms: float, players: Array) -> void:
        if b["delay_ms"] > 0.0:
                b["delay_ms"] -= delta_ms
                if b["sprite"] != null:
                        b["sprite"].modulate.a = 0.15  # marker nascosto pre-drop
                return
        match b["state"]:
                0:  # MARK: crepa pulsante — tempo di scansarsi
                        b["timer_ms"] -= delta_ms
                        if b["sprite"] != null:
                                b["sprite"].modulate.a = 0.5 \
                                                + 0.4 * sin(_time * 16.0)
                        if b["timer_ms"] <= 0.0:
                                b["state"] = 1
                                b["timer_ms"] = float(C.QUAKE_FALL_MS)
                                # il masso parte da sopra lo schermo
                                if b["sprite"] != null:
                                        b["sprite"].queue_free()
                                        b["sprite"] = null
                                b["fall_sprite"] = _make_sprite(
                                        "res://assets/sprites/hazards/boulder.png",
                                        b["cell"], 58.0)
                                b["fall_from"] = _cell_center(b["cell"]) \
                                                + Vector2(0.0, -420.0)
                                b["fall_sprite"].position = b["fall_from"]
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)
                1:  # FALL: discesa rapida verso il centro cella
                        b["timer_ms"] -= delta_ms
                        var target: Vector2 = _cell_center(b["cell"])
                        var k: float = 1.0 - clampf(
                                b["timer_ms"] / float(C.QUAKE_FALL_MS), 0.0, 1.0)
                        if b["fall_sprite"] != null:
                                b["fall_sprite"].position = b["fall_from"].lerp(target, k)
                                b["fall_sprite"].rotation += 0.35 * delta_ms / 100.0
                        if b["timer_ms"] <= 0.0:
                                _boulder_impact(b, players)
                2:  # RUBBLE: macerie che svaniscono
                        b["rubble_ms"] -= delta_ms
                        if b["sprite"] != null:
                                # dissolvenza nell'ultimo secondo
                                b["sprite"].modulate.a = clampf(
                                                b["rubble_ms"] / 1000.0, 0.0, 1.0)
                        if b["rubble_ms"] <= 0.0:
                                if b["sprite"] != null:
                                        b["sprite"].queue_free()
                                        b["sprite"] = null
                                b["done"] = true


func _boulder_impact(b: Dictionary, players: Array) -> void:
        var cell: Vector2i = b["cell"]
        var center: Vector2 = _cell_center(cell)
        # il masso si frantuma: resta solo il mucchio di macerie
        if b["fall_sprite"] != null:
                b["fall_sprite"].queue_free()
                b["fall_sprite"] = null
        b["sprite"] = _make_sprite(
                "res://assets/sprites/hazards/rubble.png", cell, 52.0)
        b["rubble_ms"] = float(C.QUAKE_RUBBLE_MS)
        b["state"] = 2  # RUBBLE: svanira' da solo
        b["done"] = false
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_THUD)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.3)
                var dust := EffectsManager.spawn_explosion(
                        center, Color(0.42, 0.38, 0.32), 20, 0.6)
                if controller != null:
                        controller.collectibles_node.add_child(dust)
        # danni da impatto: chi sta SULLA cella al momento del tonfo
        for p in players:
                if p.is_ghost() or p.is_jumping():
                        continue
                if _player_cell(p) == cell:
                        var pdmg: int = maxi(1, int(round(
                                p.max_energy * C.QUAKE_PLAYER_DAMAGE_PCT)))
                        p.take_hazard_damage(pdmg)
        if controller != null:
                for e in controller.spawner.enemies:
                        if e == null or not is_instance_valid(e) or e.is_dead():
                                continue
                        var ecell := Vector2i(
                                int(e.position.x / C.TILE_SIZE),
                                int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                        if ecell != cell:
                                continue
                        var edmg: int = maxi(1, int(round(
                                e.get_max_health() * C.QUAKE_ENEMY_DAMAGE_PCT)))
                        e.take_damage(edmg)
                        if e.is_dead():
                                var winner := _nearest_player(e.position)
                                if winner != null:
                                        winner.add_score(C.QUAKE_KILL_POINTS)
        # il masso innesca un eventuale barile sulla cella (combo!)
        for other in hazard_list:
                if other["type"] == HazardType.BARREL \
                                and other["cell"] == cell \
                                and other["state"] == BarrelState.INTACT:
                        other["state"] = BarrelState.FUSE
                        other["timer_ms"] = 1.0


# ===========================================================================
# QUERY (per test e debug)
# ===========================================================================

func count_by_type(t: int) -> int:
        var n := 0
        for h in hazard_list:
                if h["type"] == t:
                        n += 1
        return n


func find_first(t: int) -> Dictionary:
        for h in hazard_list:
                if h["type"] == t:
                        return h
        return {}

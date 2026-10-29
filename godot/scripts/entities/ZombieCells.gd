## ZombieCells.gd - TASK 81.2: CELLE ZOMBIE nei muri del labirinto.
## ============================================================
## Meccanica (richiesta utente):
##   * Nei muri ci sono celle con zombie dentro, visibili dalle sbarre.
##   * A intervalli casuali dalle sbarre escono le BRACCIA dello zombie
##     (env/zombie_arms_sheet.png, 4 frame "flexing"): se toccano il
##     player tolgono il 20% dell'energia massima ad ogni tocco
##     (invulnerabilita' post-colpo ~1s standard del Player).
##   * Le braccia restano fuori e si dimenano per 5 secondi, poi si
##     ritraggono; quindi escono nuovamente dopo un intervallo casuale.
##   * Massimo 3 celle per livello, ben distanziate tra loro; il numero
##     cresce col livello (1 ai livelli 1-3, 2 ai 4-6, 3 dal 7 in poi).
##   * Il player NON puo' schivare le braccia: riempiono l'intera cella
##     corridoio davanti alla finestra (unico varco: il corridoio e'
##     largo una cella). Puo' solo attendere la ritrazione — o attraversare
##     pagando il danno del tocco.
##
## TASK 81b — CORREZIONE GRAFICA UTENTE (niente "quadrato bianco"):
## il vecchio zombie_cell.png (blocco PixelLab OPACO con sfondo pietra
## grigia chiara) copriva il muro scuro del Task 80 e, ruotato verso il
## corridoio, capovolgeva il volto. Ora la cella e' INTEGRATA NEL MURO:
##   * finestrella procedurale (cornice + interno + sbarre) con colori
##     DERIVATI dal wall_color del livello -> stessa tinta del muro su
##     tutte le 8 palette, per costruzione (bordo pietra LEGGERMENTE piu'
##     scuro del muro: cella incassata, mai un quadrato chiaro);
##   * volto zombie (env/zombie_face.png, PixelLab TRASPARENTE) disegnato
##     in SPAZIO SCHERMO: sempre DIRITTO dietro le sbarre, mai ruotato;
##   * glow verde pulsante nel buio della cella;
##   * braccia in spazio locale ruotato (+x = facciata) CLIPPATE alla
##     facciata del muro: spuntano esattamente DENTRO il muro originale,
##     riempiono solo la cella corridoio e non sbordano oltre.
##
## Piazzamento: RNG SEEDATO sul livello (pattern MazeHazards.generate:
## al continue le celle tornano negli stessi punti della stessa griglia,
## con stati freschi). Vincoli: cella WALL statica (non lastra mobile del
## Task 30, non cella torcia), con adiacente corridoio EMPTY che ne diventa
## la facciata, distante dallo spawn del player, distanza minima Manhattan
## 8 tra celle (fallback progressivo se il labirinto e' strano).
##
## Rendering: nodo tra Maze e Hazards in MainGame.tscn. Il muro resta
## DISegnato dal Maze (texture roccia scura Task 80): la finestrella della
## cella e' solo un velo SOPRA la piastrella muro, con la cornice derivata
## dal wall_color del livello ("dello stesso colore del muro").
## ============================================================
extends Node2D
class_name ZombieCells

const C = preload("res://scripts/core/GameConstants.gd")

enum CellPhase { IDLE, EMERGE, OUT, RETRACT }

# Slide massima delle braccia = 1 cella corridoio (64px).
const SLIDE_FULL_PX: float = 64.0
# Slide oltre la quale le braccia fanno danno (la punta supera il centro
# della cella corridoio: da qui in poi il tocco e' inevitabile).
const SLIDE_DAMAGE_PX: float = 32.0
# Margine (px) della zona danno attorno alla cella corridoio.
const ZONE_MARGIN_PX: float = 8.0
# Durata frame dello sheet braccia (flexing 4 frame).
const ARMS_FRAME_MS: int = 220

# --- TASK 81b: geometria finestrella cella (px, spazio piastrella 64) ---
# Offset del centro finestra verso la facciata (la cornice esterna 50px
# arriva a filo della facciata: "porta di cella" sullo spigolo del muro).
const WIN_OFFSET_PX: float = 7.0
# Larghezza apertura interna (buio della cella) e canvas del volto (draw 1:1).
const WIN_INNER_PX: float = 42.0
const FACE_PX: float = 40.0
# Raggio del glow verde pulsante dentro la cella.
const GLOW_RADIUS_PX: float = 26.0
# Sbarre in ferro scuro (fisso: leggibili sul buio di ogni palette) con
# bordo sinistro leggermente piu' chiaro (spigolo colpito dalla luce).
const COL_BAR: Color = Color(0.055, 0.055, 0.070, 1.0)
const COL_BAR_HI: Color = Color(0.210, 0.210, 0.240, 1.0)

# --- Texture PixelLab (cache static: upload GPU una volta a vita) ---
static var _face_tex_cache: Texture2D = null
static var _face_tex_tried: bool = false
static var _arms_tex_cache: Texture2D = null
static var _arms_tex_tried: bool = false
static var _glow_tex_cache: Texture2D = null

# --- Stato ---
var _level: int = 1
var _time_ms: float = 0.0
var _cells: Array = []  # dizionari-stato per cella zombie
var _rng := RandomNumberGenerator.new()

# Colori cella derivati dal wall_color del livello (cachati in generate:
# la finestrella e' DEL COLORE DEL MURO, il buio della cella e' lo stesso
# colore quasi spento). TASK 81b.
var _col_lip: Color = Color(0.377, 0.351, 0.325, 1.0)
var _col_shadow: Color = Color(0.131, 0.122, 0.113, 1.0)
var _col_interior: Color = Color(0.081, 0.076, 0.070, 1.0)


static func _get_face_texture() -> Texture2D:
        if _face_tex_tried:
                return _face_tex_cache
        _face_tex_tried = true
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/env/zombie_face.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _face_tex_cache = ImageTexture.create_from_image(img)
        return _face_tex_cache


## Glow verde: texture radiale bianca 96x96 (falloff quadratico, core
## pieno — pattern _get_lantern_pool_texture del Maze, Task 80): il verde
## passa via modulate al draw. Cache static UNICA (un upload GPU a vita).
static func _get_glow_texture() -> Texture2D:
        if _glow_tex_cache != null:
                return _glow_tex_cache
        const GLOW_SIZE: int = 96
        var img := Image.create(GLOW_SIZE, GLOW_SIZE, false, Image.FORMAT_RGBA8)
        var center := Vector2(GLOW_SIZE / 2.0, GLOW_SIZE / 2.0)
        for y in range(GLOW_SIZE):
                for x in range(GLOW_SIZE):
                        var d: float = Vector2(x, y).distance_to(center) / (GLOW_SIZE / 2.0)
                        var a: float = clampf(1.0 - d, 0.0, 1.0)
                        a = clampf(a * a * 1.25, 0.0, 1.0)
                        img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
        _glow_tex_cache = ImageTexture.create_from_image(img)
        return _glow_tex_cache


static func _get_arms_texture() -> Texture2D:
        if _arms_tex_tried:
                return _arms_tex_cache
        _arms_tex_tried = true
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/env/zombie_arms_sheet.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _arms_tex_cache = ImageTexture.create_from_image(img)
        return _arms_tex_cache


## Genera le celle per il livello. Chiamato da MainGameController.start_level
## DOPO maze.generate e hazards.generate (le lastre mobili del Task 30 sono
## gia' registrate in maze.dynamic_walls e vengono escluse).
func generate(lvl: int, maze: Node) -> void:
        _cells.clear()
        _level = lvl
        _time_ms = 0.0
        # TASK 81b: colori della finestrella derivati dal wall_color del
        # livello (generate() del Maze ha gia' applicato la palette). La
        # cornice e' LEGGERMENTE PIU' SCURA del muro (pietra incassata):
        # mai piu' chiara del muro, cosi' la cella non puo' leggere come
        # "quadrato chiaro" su NESSUNA palette (feedback utente).
        var wc = maze.get("wall_color") if maze != null else null
        if wc != null and wc is Color:
                _col_lip = Color(wc.r * 0.92, wc.g * 0.92, wc.b * 0.92, 1.0)
                _col_shadow = Color(wc.r * 0.55, wc.g * 0.55, wc.b * 0.55, 1.0)
                _col_interior = Color(wc.r * 0.30, wc.g * 0.30, wc.b * 0.30, 1.0)
        if not C.ZOMBIE_CELLS_ENABLED:
                queue_redraw()
                return
        _rng.seed = hash("zcells_v1_%d" % lvl)
        var wanted: int = C.zombie_cells_for_level(lvl)
        var candidates: Array = _collect_candidates(maze, lvl)
        if candidates.is_empty():
                queue_redraw()
                return
        # Piazzamento a SELEZIONE DEL PIU' LONTANO (farthest-point): le
        # candidate sono mescolate con l'RNG seedato (determinismo per il
        # continue, prima cella random), poi ogni nuova cella e' quella che
        # MASSIMIZZA la distanza minima dalle gia' piazzate -> le celle
        # "ben distanziate" si SPARGONO su tutta la mappa invece di
        # accatastarsi dove la scansione le trova prima.
        _shuffle_seeded(candidates)
        while _cells.size() < wanted:
                var best: Dictionary = {}
                var best_dist: int = -1
                for cand in candidates:
                        if _is_taken(cand):
                                continue
                        var d: int = 9999
                        for placed in _cells:
                                var pd: int = absi(int(cand["col"]) - int(placed["col"])) \
                                                + absi(int(cand["row"]) - int(placed["row"]))
                                d = mini(d, pd)
                        if d > best_dist:
                                best_dist = d
                                best = cand
                # fallback progressivo: sotto 2 celle di distanza non ha
                # piu' senso piazzare (labirinto degenere)
                if best.is_empty() or best_dist < 2:
                        break
                _cells.append(_make_cell(best))
        queue_redraw()


## Cella-stato iniziale: IDLE, prima estensione casuale in 3-8s.
func _make_cell(cand: Dictionary) -> Dictionary:
        return {
                "col": int(cand["col"]),
                "row": int(cand["row"]),
                "dir": cand["dir"],  # Vector2i unitario verso il corridoio
                "phase": CellPhase.IDLE,
                "next_out_ms": _rng.randf_range(
                                C.ZOMBIE_FIRST_OUT_MIN_MS, C.ZOMBIE_FIRST_OUT_MAX_MS),
                "out_ms": 0.0,
                "slide": 0.0,
                "phase_seed": _rng.randf() * TAU,
        }


## Candidate: celle WALL con corridoio EMPTY adiacente (la facciata), che
## non siano lastre mobili (Task 30), torce (hash [14,19) di
## Maze._spawn_torch_lights) o vicine allo spawn del player (1,1).
## NB: si escludono anche le celle ADIACENTI a un muro di roccia mobile:
## quando il passaggio e' APERTO le due lastre si ritragcono DENTRO i muri
## vicini (WALL_OPEN_OFF=64, MazeHazards) e le loro Sprite2D — disegnate
## sopra questo nodo — coprirebbero il blocco-cella pieno con la roccia.
func _collect_candidates(maze: Node, lvl: int) -> Array:
        var out: Array = []
        if maze == null:
                return out
        for c in range(1, C.MAZE_COLS - 1):
                for r in range(1, C.MAZE_ROWS - 1):
                        if not maze.is_wall(c, r):
                                continue
                        if maze.dynamic_walls.has("%d,%d" % [c, r]):
                                continue
                        # niente celle dove il Maze disegna una torcia
                        var h: int = (c * 73856093) ^ (r * 19349663) ^ (lvl * 83492791)
                        var hash_val: int = abs(h) % 100
                        if hash_val >= 14 and hash_val < 19:
                                continue
                        # niente braccia in faccia allo spawn del player
                        if absi(c - 1) + absi(r - 1) < C.ZOMBIE_CELLS_MIN_DIST_SPAWN:
                                continue
                        # niente celle coperte dalle lastre di roccia retratte
                        # del muro mobile vicino (vedi commento funzione)
                        var slab_neighbor: bool = false
                        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                                if maze.dynamic_walls.has("%d,%d" % [c + d.x, r + d.y]):
                                        slab_neighbor = true
                                        break
                        if slab_neighbor:
                                continue
                        var dirs: Array = []
                        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                                var nc: int = c + d.x
                                var nr: int = r + d.y
                                if nc < 0 or nc >= C.MAZE_COLS or nr < 0 or nr >= C.MAZE_ROWS:
                                        continue
                                if not maze.is_wall(nc, nr):
                                        dirs.append(d)
                        if dirs.is_empty():
                                continue
                        out.append({
                                "col": c,
                                "row": r,
                                "dir": dirs[_rng.randi() % dirs.size()],
                        })
        return out


func _is_taken(cand: Dictionary) -> bool:
        for placed in _cells:
                if int(placed["col"]) == int(cand["col"]) \
                                and int(placed["row"]) == int(cand["row"]):
                        return true
        return false


## Fisher-Yates con l'RNG seedato del livello (Array.shuffle() userebbe il
## RNG globale e romperebbe il determinismo del continue).
func _shuffle_seeded(arr: Array) -> void:
        for i in range(arr.size() - 1, 0, -1):
                var j: int = _rng.randi_range(0, i)
                var tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp


## Update delle celle (chiamato da MainGameController._update_playing con
## la lista dei player VIVI: i morti non possono essere toccati).
func update_cells(delta_ms: float, players: Array) -> void:
        _time_ms += float(delta_ms)
        if _cells.is_empty():
                return
        for cell in _cells:
                _advance_phase(cell, delta_ms)
        _apply_damage(players)
        queue_redraw()


func _advance_phase(cell: Dictionary, delta_ms: float) -> void:
        match cell["phase"]:
                CellPhase.IDLE:
                        cell["next_out_ms"] -= float(delta_ms)
                        if cell["next_out_ms"] <= 0.0:
                                cell["phase"] = CellPhase.EMERGE
                CellPhase.EMERGE:
                        cell["slide"] = minf(SLIDE_FULL_PX,
                                        cell["slide"] + SLIDE_FULL_PX * float(delta_ms) / C.ZOMBIE_EMERGE_MS)
                        if cell["slide"] >= SLIDE_FULL_PX:
                                cell["phase"] = CellPhase.OUT
                                cell["out_ms"] = C.ZOMBIE_ARM_OUT_MS
                CellPhase.OUT:
                        cell["out_ms"] -= float(delta_ms)
                        # dimenio continuo: la slide oscilla attorno al pieno
                        cell["slide"] = SLIDE_FULL_PX + sin(
                                        _time_ms * 0.012 + cell["phase_seed"]) * 4.0
                        if cell["out_ms"] <= 0.0:
                                cell["phase"] = CellPhase.RETRACT
                CellPhase.RETRACT:
                        cell["slide"] = maxf(0.0,
                                        cell["slide"] - SLIDE_FULL_PX * float(delta_ms) / C.ZOMBIE_EMERGE_MS)
                        if cell["slide"] <= 0.0:
                                cell["phase"] = CellPhase.IDLE
                                cell["next_out_ms"] = _next_out_interval()


## Intervallo casuale della prossima estensione (si accorcia un po' col
## livello: pressione crescente, come i fantasmi).
func _next_out_interval() -> float:
        var k: float = clampf(float(_level - 1) / 11.0, 0.0, 1.0)
        var sc: float = lerpf(1.0, C.ZOMBIE_OUT_FAST_SCALE, k)
        return _rng.randf_range(C.ZOMBIE_OUT_MIN_MS * sc, C.ZOMBIE_OUT_MAX_MS * sc)


## Danno: per ogni cella con braccia sufficientemente estese, se un player
## vivo tocca la cella corridoio davanti alla facciata -> 20% energia max
## (arrotondato, min 1). L'invulnerabilita' post-tocco (~1s) e la gestione
## morte/vita persa sono gia' dentro Player.take_hazard_damage (pattern
## ganasce/voragini: BYPASS armature, danno ambientale del dungeon).
## TASK 81 (spec utente): unblockable=true — il SALTO NON protegge
## ("Il player non puo' schivare le braccia ma solo attendere le vengano
## ritratte"): si subisce il tocco finche' le braccia restano estese.
func _apply_damage(players: Array) -> void:
        for cell in _cells:
                if float(cell["slide"]) < SLIDE_DAMAGE_PX:
                        continue
                var zone: Rect2 = _damage_zone(cell)
                for p in players:
                        if p == null or not is_instance_valid(p):
                                continue
                        if zone.has_point(p.position):
                                var dmg: int = maxi(1, int(round(
                                                p.max_energy * C.ZOMBIE_ARM_DAMAGE_PCT)))
                                p.take_hazard_damage(dmg, true)


## Zona danno: la cella corridoio davanti alla facciata (+ margine), in
## coordinate mondo dello spazio MainGame (le braccia riempiono il varco:
## il player grid-locked passa SEMPRE per il centro di quella cella).
func _damage_zone(cell: Dictionary) -> Rect2:
        var cc: int = int(cell["col"]) + int(cell["dir"].x)
        var rr: int = int(cell["row"]) + int(cell["dir"].y)
        return Rect2(
                        float(cc * C.TILE_SIZE) - ZONE_MARGIN_PX,
                        float(C.UI_HEIGHT + rr * C.TILE_SIZE) - ZONE_MARGIN_PX,
                        float(C.TILE_SIZE) + ZONE_MARGIN_PX * 2.0,
                        float(C.TILE_SIZE) + ZONE_MARGIN_PX * 2.0)


func _draw() -> void:
        if _cells.is_empty():
                return
        var face_tex: Texture2D = _get_face_texture()
        var arms_tex: Texture2D = _get_arms_texture()
        var glow_tex: Texture2D = _get_glow_texture()
        var frame: int = (int(_time_ms) / ARMS_FRAME_MS) % 4
        for cell in _cells:
                var center := Vector2(
                                int(cell["col"]) * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                                C.UI_HEIGHT + int(cell["row"]) * C.TILE_SIZE + C.TILE_SIZE * 0.5)
                var dir: Vector2i = cell["dir"]
                # -------- 1. BRACCIA (spazio locale ruotato: +x = facciata).
                # TASK 81b: niente piu' blocco-copertura: le braccia sono
                # CLIPPATE al tratto oltre la facciata (x in [32, 96], cioe'
                # la sola cella corridoio). Emergono esattamente dalla
                # facciata del muro originale e non sbordano oltre.
                var slide: float = float(cell["slide"])
                if arms_tex != null and slide > 0.5:
                        var angle: float = atan2(float(dir.y), float(dir.x))
                        draw_set_transform(center, angle)
                        var x0: float = slide - 32.0
                        var x1: float = x0 + 64.0
                        const CLIP_LO: float = 32.0  # facciata muro/corridoio
                        const CLIP_HI: float = 96.0  # fondo cella corridoio
                        if x1 > CLIP_LO and x0 < CLIP_HI:
                                var lo: float = maxf(x0, CLIP_LO)
                                var hi: float = minf(x1, CLIP_HI)
                                # mappa 1:1 il tratto visibile del frame
                                draw_texture_rect_region(arms_tex,
                                                Rect2(lo, -32.0, hi - lo, 64.0),
                                                Rect2(float(frame) * 64.0 + (lo - x0),
                                                                0.0, hi - lo, 64.0),
                                                Color.WHITE, false, false)
                        draw_set_transform(Vector2.ZERO, 0.0)
                # -------- 2. FINESTRELLA CELLA (spazio schermo: volto DIRITTO).
                # Tre veli sulla piastrella muro, tutti PIU' SCURI del muro
                # (cella incassata: bordo pietra quasi come il muro, ombra
                # sotto il bordo, buio interno) -> stessa tinta del muro,
                # mai un quadrato chiaro (feedback utente TASK 81b).
                var wc := Vector2(center.x + float(dir.x) * WIN_OFFSET_PX,
                                center.y + float(dir.y) * WIN_OFFSET_PX)
                var half_i: float = WIN_INNER_PX * 0.5
                draw_rect(Rect2(wc.x - half_i - 4.0, wc.y - half_i - 4.0,
                                WIN_INNER_PX + 8.0, WIN_INNER_PX + 8.0), _col_lip)
                draw_rect(Rect2(wc.x - half_i - 2.0, wc.y - half_i - 2.0,
                                WIN_INNER_PX + 4.0, WIN_INNER_PX + 4.0), _col_shadow)
                draw_rect(Rect2(wc.x - half_i, wc.y - half_i,
                                WIN_INNER_PX, WIN_INNER_PX), _col_interior)
                # glow verde pulsante nel buio (il verde spinge il volto e
                # le sbarre a leggersi per contrasto, pattern lanterne 80).
                if glow_tex != null:
                        var pulse: float = 0.22 + 0.07 * sin(
                                        _time_ms * 0.0016
                                        + float(cell["phase_seed"]) * 3.0)
                        var gcol := Color(0.30, 0.85, 0.40, clampf(pulse, 0.0, 1.0))
                        draw_texture_rect(glow_tex, Rect2(
                                        wc.x - GLOW_RADIUS_PX, wc.y - GLOW_RADIUS_PX,
                                        GLOW_RADIUS_PX * 2.0, GLOW_RADIUS_PX * 2.0),
                                        false, gcol, false)
                # volto zombie PixelLab: sempre DIRITTO (spazio schermo),
                # mai ruotato qualunque sia la direzione della facciata.
                if face_tex != null:
                        draw_texture_rect(face_tex, Rect2(
                                        wc.x - FACE_PX * 0.5, wc.y - FACE_PX * 0.5,
                                        FACE_PX, FACE_PX), false)
                # sbarre verticali in ferro: 4 barre da 3px (1px di bordo
                # chiaro a sinistra = spigolo colpito dalla luce) sopra al volto.
                for bx in [-15.0, -5.0, 5.0, 15.0]:
                        draw_rect(Rect2(wc.x + bx - 1.5, wc.y - half_i + 2.0,
                                        3.0, WIN_INNER_PX - 4.0), COL_BAR)
                        draw_rect(Rect2(wc.x + bx - 1.5, wc.y - half_i + 2.0,
                                        1.0, WIN_INNER_PX - 4.0), COL_BAR_HI)


# ============================================================================
# API di introspezione (per i test headless tests/test_maze81.gd)
# ============================================================================
func cell_count() -> int:
        return _cells.size()


func cell_positions() -> Array:
        var out: Array = []
        for cell in _cells:
                out.append(Vector2i(int(cell["col"]), int(cell["row"])))
        return out


func cell_phase(col: int, row: int) -> int:
        for cell in _cells:
                if int(cell["col"]) == col and int(cell["row"]) == row:
                        return int(cell["phase"])
        return -1


## Direzione (Vector2i unitario) della facciata: la cella corridoio dove
## spuntano le braccia. Per i test e per il debugging.
func cell_facing(col: int, row: int) -> Vector2i:
        for cell in _cells:
                if int(cell["col"]) == col and int(cell["row"]) == row:
                        return cell["dir"]
        return Vector2i.ZERO


func force_out(col: int, row: int) -> bool:
        ## Helper test: forza la cella in EMERGE immediatamente.
        for cell in _cells:
                if int(cell["col"]) == col and int(cell["row"]) == row:
                        cell["next_out_ms"] = 0.0
                        return true
        return false

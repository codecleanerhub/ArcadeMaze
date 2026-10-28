## ZombieCells.gd - TASK 81.2: CELLE ZOMBIE nei muri del labirinto.
## ============================================================
## Meccanica (richiesta utente):
##   * Nei muri ci sono celle con zombie dentro, visibili dalle sbarre
##     (blocco pietra + finestra inferriata + volto zombie: PixelLab
##     env/zombie_cell.png).
##   * A intervalli casuali dalle sbarre escono le BRACCIA dello zombie
##     (env/zombie_arms_sheet.png, slide da dietro il blocco): se toccano
##     il player tolgono il 20% dell'energia massima ad ogni tocco
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
## Piazzamento: RNG SEEDATO sul livello (pattern MazeHazards.generate:
## al continue le celle tornano negli stessi punti della stessa griglia,
## con stati freschi). Vincoli: cella WALL statica (non lastra mobile del
## Task 30, non cella torcia), con adiacente corridoio EMPTY che ne diventa
## la facciata, distante dallo spawn del player, distanza minima Manhattan
## 8 tra celle (fallback progressivo se il labirinto e' strano).
##
## Rendering: nodo tra Maze e Hazards in MainGame.tscn — il blocco copre la
## texture roccia della sua cella; le braccia sono disegnate PRIMA del
## blocco e scorrono da dietro (slide 0->64px), quindi spuntano esattamente
## dalla facciata con le sbarre. Ogni cella disegna in uno spazio locale
## ruotato verso il proprio corridoio (facciata = +x locale).
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

# --- Texture PixelLab (cache static: 2 upload GPU a vita) ---
static var _cell_tex_cache: Texture2D = null
static var _cell_tex_tried: bool = false
static var _arms_tex_cache: Texture2D = null
static var _arms_tex_tried: bool = false

# --- Stato ---
var _level: int = 1
var _time_ms: float = 0.0
var _cells: Array = []  # dizionari-stato per cella zombie
var _rng := RandomNumberGenerator.new()


static func _get_cell_texture() -> Texture2D:
        if _cell_tex_tried:
                return _cell_tex_cache
        _cell_tex_tried = true
        var abs_path: String = ProjectSettings.globalize_path(
                        "res://assets/sprites/env/zombie_cell.png")
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _cell_tex_cache = ImageTexture.create_from_image(img)
        return _cell_tex_cache


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
        var cell_tex: Texture2D = _get_cell_texture()
        var arms_tex: Texture2D = _get_arms_texture()
        var frame: int = (int(_time_ms) / ARMS_FRAME_MS) % 4
        for cell in _cells:
                var center := Vector2(
                                int(cell["col"]) * C.TILE_SIZE + C.TILE_SIZE * 0.5,
                                C.UI_HEIGHT + int(cell["row"]) * C.TILE_SIZE + C.TILE_SIZE * 0.5)
                # spazio locale: +x = facciata verso il corridoio
                var angle: float = atan2(float(cell["dir"].y), float(cell["dir"].x))
                draw_set_transform(center, angle)
                if arms_tex != null and float(cell["slide"]) > 0.5:
                        # braccia PRIMA del blocco: scorrono da dietro — la
                        # parte dentro il blocco resta coperta dalla pietra.
                        var slide: float = float(cell["slide"])
                        var src := Rect2(float(frame) * 64.0, 0.0, 64.0, 64.0)
                        var dst := Rect2(slide - 64.0 + 32.0, -32.0, 64.0, 64.0)
                        draw_texture_rect_region(arms_tex, dst, src, Color.WHITE, false, false)
                if cell_tex != null:
                        # blocco-cella pieno: copre la texture roccia del muro
                        draw_texture_rect(cell_tex, Rect2(-32.0, -32.0, 64.0, 64.0), false)
                draw_set_transform(Vector2.ZERO, 0.0)


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

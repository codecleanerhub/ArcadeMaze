## Maze.gd - Procedural maze generation and rendering.
##
## Faithful Godot port of Maze.h / Maze.cpp from the SFML/C++ version.
##
## ## Grid conventions
##  - The grid is `MAZE_COLS` x `MAZE_ROWS` = 21 x 19 cells.
##  - Each cell is `TILE_SIZE` = 48 px.
##  - Coordinate order is `[col][row]`, matching the C++ `grid[c][r]` access.
##  - The maze is drawn below the UI bar: pixel y of cell (c, r) is
##    `r * TILE_SIZE + UI_HEIGHT`.
##
## ## Generation algorithm (1:1 from Maze.cpp::generate)
##  1. Fill everything with WALL.
##  2. Iterative DFS ("recursive backtracker") digging 2 cells at a time.
##  3. Open ~15 extra walls with exactly 2 wall-neighbors to create loops.
##  4. Place 8 treasures and 5 weapons, all minimum Manhattan-distance apart.
##  5. Pick one of 8 color palettes based on `(level - 1) % 8`.
##
## ## Rendering
## The C++ code renders the maze with hundreds of lines of SFML primitives
## for a "rocky dungeon" look. This port reproduces the *structure* of that
## rendering (floor gradient, 5-band vertical gradient per wall, treasure
## pedestal and weapons) using Godot's `_draw()` callback. The procedural
## details can be progressively enriched; the public API and the cell data
## are what other scripts depend on.
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

# ============================================================================
# SIGNALS
# ============================================================================
## Emitted whenever a new maze has been generated. Listeners (Player, UI)
## use this to reposition / refresh.
signal maze_generated(level: int)
## Emitted when a treasure cell is collected.
signal treasure_collected(col: int, row: int, treasure_type: int)
## Emitted when a weapon cell is collected.
signal weapon_collected(col: int, row: int, weapon_type: int)
## Emitted when the last treasure is collected (i.e. remaining hits 0).
signal all_treasures_collected

# ============================================================================
# PUBLIC STATE
# ============================================================================
## The level this maze belongs to (1-based). Drives the color palette and
## difficulty scaling (handled by Player/Enemy scenes).
@export var level: int = 1

## When true, the maze is redrawn on the next `_draw` call. Set to true
## automatically by `generate()` and by every cell mutation; flip it back
## to false if you draw to an offscreen buffer.
@export var needs_redraw: bool = true

# ============================================================================
# INTERNAL GRID
# ============================================================================
# We store the grid as a flat PoolByteArray-like Array of dictionaries so
# the per-cell fields (type, treasure, weapon) match the C++ `Cell` struct
# layout. Each entry is: { "type": int, "treasure": int, "weapon": Dictionary }.
#
# Using a flat Array indexed by `col * MAZE_ROWS + row` keeps lookups O(1)
# and avoids nested-array overhead in GDScript.
var _grid: Array = []

## Wall color for the current palette (read by external renderers).
var wall_color: Color = Color(0.29, 0.27, 0.25, 1.0)

## TASK 30 (muri di roccia mobili): registro delle celle WALL che un
## muro di roccia del MazeHazards apre/chiude ciclicamente.
## Chiave "c,r" -> true = muro CHIUSO, false = muro APERTO (attraversabile).
## is_wall() consulta il registro PRIMA del tipo statico: la scorciatoia
## e' percorsibile da player/proiettili/BFS solo mentre e' aperta, e il
## rendering la disegna come pavimento (le due lastre di roccia che
## scorrono sono la parete visibile). Popolato/ripulito dal MazeHazards.
var dynamic_walls: Dictionary = {}
## Floor color for the current palette (TASK 80: ripristinato il valore
## scuro originale — la visibilita' ora arriva dalle lanterne, vedi
## _draw_lantern_floor_pools).
var bg_color: Color = Color(0.11, 0.09, 0.07, 1.0)

# 8 color palettes that cycle per level (1:1 from Maze.cpp).
#  Index 0 = grey cavern, 1 = blue dungeon, 2 = purple crypt, 3 = red rock,
#  4 = bone ossuary, 5 = green swamp, 6 = red hell, 7 = teal abyss.
#  TASK 80 (feedback utente: "i muri non devono essere cosi' chiari... siamo
#  in un dungeon quindi ha senso avere toni piu' scuri mentre il pavimento
#  l'hai reso troppo chiaro — potresti usare effetti di luce delle lanterne
#  per rendere piu' chiaro il pavimento?"): ROLLBACK COMPLETO del TASK 79d —
#  i bg tornano ai valori ORIGINALI scuri (~0.06-0.14, sotto i muri: e' un
#  dungeon). La visibilita' del player scuro (elf) e dei nemici scuri non
#  arriva piu' dal pavimento chiaro uniforme ma dalle LANTERNE:
#    - pozza di luce calda bakeata sul pavimento per OGNI torcia
#      (_draw_lantern_floor_pools, flicker sincrono con la fiamma);
#    - alone caldo SOPRA i muri vicino alle torce (_draw_lantern_wall_halos);
#    - lanterna dell'eroe: pozza che segue i player vivi
#      (player_light_positions, aggiornata dal MainGameController);
#    - 6 PointLight2D ridistribuite su tutta la mappa (raggio 80->140).
#  Rollback delle lanterne: GameConstants.LANTERN_LIGHT_ENABLED = false.
#  Rollback pavimento/muri: git revert del TASK 79d / TASK 78 (vedi worklog).
#  Il gradiente radiale centrale (+24/255 al centro) resta invariato.
const _PALETTES: Array = [
        {"wall": Color(0.294, 0.275, 0.255), "bg": Color(0.110, 0.086, 0.071)},  # 0 grey cavern
        {"wall": Color(0.216, 0.275, 0.353), "bg": Color(0.071, 0.086, 0.137)},  # 1 blue dungeon
        {"wall": Color(0.333, 0.235, 0.353), "bg": Color(0.110, 0.071, 0.118)},  # 2 purple crypt
        {"wall": Color(0.373, 0.235, 0.196), "bg": Color(0.137, 0.078, 0.059)},  # 3 red rock
        {"wall": Color(0.373, 0.333, 0.235), "bg": Color(0.125, 0.110, 0.071)},  # 4 bone ossuary
        {"wall": Color(0.235, 0.314, 0.216), "bg": Color(0.071, 0.110, 0.071)},  # 5 green swamp
        {"wall": Color(0.373, 0.196, 0.176), "bg": Color(0.137, 0.059, 0.047)},  # 6 red hell
        {"wall": Color(0.176, 0.333, 0.333), "bg": Color(0.059, 0.110, 0.118)},  # 7 teal abyss
]

# ============================================================================
# PROCEDURAL ROCKY WALL TEXTURE CACHE
# ============================================================================
# Cache static: 8 texture rocciose (una per palette). Generate una tantum
# via FastNoiseLite (Simplex Smooth fine + Cellular macro-blocchi + Perlin
# Ridged per fratture) e tinteggiate con wall_color del livello.
# Sostituisce le 5 draw_rect sovrapposte (sintomo "rettangoli sfumati") con
# una singola draw_texture_rect_region + highlight/ombra per effetto 3D.
static var _rock_texture_cache: Dictionary = {}  # key=pal_idx -> ImageTexture

# Variabile di istanza: texture corrente per il livello (riferimento alla cache).
var _rock_tex: Texture2D = null


# Genera una texture rocciosa procedurale 128x128 via FastNoiseLite.
# Composta da 3 strati di rumore:
#   1. Simplex Smooth (frequency=0.18) -> granaglia fine superficiale
#   2. Cellular (frequency=0.04, jitter=0.8) -> macro-blocchi rocciosi
#   3. Perlin Ridged frattale (3 ottave, frequency=0.08) -> venature/crepacci
# Tinteggiata con base_color (wall_color del livello) per mantenere la
# varietà di colore per livello. Aggiunge linee di "fuga" tra mattoni ogni
# 32px (con offset alternato come un muro a mattoni) per stile dungeon.
static func _generate_rock_texture(pal_idx: int, base_color: Color) -> ImageTexture:
        if _rock_texture_cache.has(pal_idx):
                return _rock_texture_cache[pal_idx]
        const TEX_SIZE: int = 128
        var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
        # --- TASK 57: texture roccia PixelLab (luminanza) + tint palette ---
        # La texture PNG (grayscale normalizzata full-range) fornisce la
        # LUMINANZA per pixel; il colore resta quello della palette livello.
        # TASK 80 (rollback TASK 78): ripristinata la mappa ORIGINALE
        # 0.25x-1.45x (stessa del noise procedurale). Rollback:
        # GameConstants.WALL_ROCK_PIXELLAB_ENABLED = false.
        # NB: usa la STESSA var img dichiarata sopra (lezione 12.18: mai
        # ridichiarare var omonima nello stesso scope — parse error runtime).
        if C.WALL_ROCK_PIXELLAB_ENABLED:
                var rock: Image = _load_pixellab_rock()
                if rock != null:
                        for y in range(TEX_SIZE):
                                for x in range(TEX_SIZE):
                                        var c57: Color = rock.get_pixel(x, y)
                                        var lum57: float = c57.r * 0.299 + c57.g * 0.587 + c57.b * 0.114
                                        # TASK 80 (feedback utente: "i muri del
                                        # labirinto non devono essere cosi' chiari,
                                        # ripristina il colore dei muri, siamo in un
                                        # dungeon quindi ha senso avere toni piu'
                                        # scuri"): ROLLBACK della curva compressa
                                        # del TASK 78 (t = 0.75 + lum*0.55, range
                                        # 0.75-1.30) e RIPRISTINO della mappa
                                        # ORIGINALE del Task 57:
                                        # t = 0.25 + lum*1.20 (range 0.25-1.45).
                                        # I contorni scuri dei massi PixelLab
                                        # (lum 0.05-0.30) tornano zone scure
                                        # t 0.31-0.61 = toni dungeon; le crepe
                                        # profonde si leggono di nuovo e i muri
                                        # stanno SOPRA il pavimento come nel C++.
                                        # La luce delle lanterne (TASK 80) riprende
                                        # i muri vicino alle torce con l'alone
                                        # caldo (_draw_lantern_wall_halos).
                                        var t57: float = 0.25 + lum57 * 1.20
                                        img.set_pixel(x, y, Color(
                                                clampf(base_color.r * t57, 0.0, 1.0),
                                                clampf(base_color.g * t57, 0.0, 1.0),
                                                clampf(base_color.b * t57, 0.0, 1.0), 1.0))
                        var tex57 := ImageTexture.create_from_image(img)
                        _rock_texture_cache[pal_idx] = tex57
                        return tex57
        var noise_fine := FastNoiseLite.new()
        noise_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
        noise_fine.frequency = 0.18
        noise_fine.seed = 1000 + pal_idx * 17
        var noise_macro := FastNoiseLite.new()
        noise_macro.noise_type = FastNoiseLite.TYPE_CELLULAR
        noise_macro.frequency = 0.04
        # FIX (errore Godot 4.7 parse): in Godot 4.7 le enum di FastNoiseLite
        # sono flat (FastNoiseLite.DISTANCE_EUCLIDEAN), MA il type-checker
        # rifiuta l'assegnazione diretta perché le considera 'int'. La sub-enum
        # FastNoiseLite.CellularDistance.DISTANCE_EUCLIDEAN NON esiste (errore
        # "Cannot find member CellularDistance").
        # Soluzione: omettere l'assegnazione — il valore default di
        # cellular_distance è già DISTANCE_EUCLIDEAN, quindi non serve.
        # Si imposta solo cellular_jitter per il macro-blocco roccioso.
        noise_macro.cellular_jitter = 0.8
        noise_macro.seed = 2000 + pal_idx * 23
        var noise_fracture := FastNoiseLite.new()
        noise_fracture.noise_type = FastNoiseLite.TYPE_PERLIN
        noise_fracture.frequency = 0.08
        noise_fracture.fractal_type = FastNoiseLite.FRACTAL_RIDGED
        noise_fracture.fractal_octaves = 3
        noise_fracture.seed = 3000 + pal_idx * 31
        # (img e' gia' dichiarata in testa alla funzione — TASK 57)
        # FIX (muri ancora più rocciosi/porosi): aumentato ancora il contrasto
        # e aggiunto più variazione. La composizione ora dà più peso al rumore
        # fine (granaglia) e fracture (crepacci) per un effetto più "grezzo"
        # e roccioso, meno uniforme. Mapping più ampio per ombre profonde e
        # highlight brillanti.
        for y in range(TEX_SIZE):
                for x in range(TEX_SIZE):
                        var n_fine: float = noise_fine.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
                        var n_macro: float = noise_macro.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
                        var n_fract: float = noise_fracture.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
                        # Macro domina per blocchi rocciosi, fine dettaglia,
                        # fracture dà profondità (crepacci).
                        # Peso maggiore a fine+fracture per effetto più poroso.
                        var shade: float = n_macro * 0.40 + n_fine * 0.35 + n_fract * 0.25
                        # Crepacci profondi: dove fracture è basso, scurisce MOLTO
                        if n_fract < 0.40:
                                shade -= (0.40 - n_fract) * 1.6
                        # Highlight forte: dove macro è alto e fine è alto, schiarisci
                        if n_macro > 0.60 and n_fine > 0.55:
                                shade += (n_macro - 0.60) * 0.7
                        # Porosità: piccoli "buchi" neri dove fine è molto basso
                        if n_fine < 0.20:
                                shade -= (0.20 - n_fine) * 1.2
                        shade = clampf(shade, 0.0, 1.0)
                        # Mapping molto ampio: 0.25x (ombra quasi nera) -> 1.45x
                        # (highlight roccia molto illuminata). Effetto roccia
                        # porosa grotta scavata, non più mattoni uniformi.
                        var t: float = 0.25 + shade * 1.20
                        var r: float = clampf(base_color.r * t, 0.0, 1.0)
                        var g: float = clampf(base_color.g * t, 0.0, 1.0)
                        var b: float = clampf(base_color.b * t, 0.0, 1.0)
                        img.set_pixel(x, y, Color(r, g, b, 1.0))
        # FIX (roccia grotta scavata, non mattoni): rimosse le linee di fuga
        # tra mattoni (ogni 32px con offset alternato) che davano l'effetto
        # "muro di mattoni". La texture ora è puramente roccia irregolare con
        # crepacci naturali generati dal rumore Perlin Ridged.
        var tex := ImageTexture.create_from_image(img)
        _rock_texture_cache[pal_idx] = tex
        return tex


# Per-cell placement constants (from Maze.cpp).
const _NUM_EXTRA_OPENINGS: int = 15
# FIX (richiesta utente — tesori -20%): i tesori da raccogliere passano da 8
# a 6 (-20% = 8 - 1.6, arrotondato per difetto al valore intero piu' vicino
# che rispetta il vincolo di distanza minima 4 su griglia 30x15).
const _TREASURES_PER_LEVEL: int = 6
const _WEAPONS_PER_LEVEL: int = 5
const _MIN_DIST_TREASURE: int = 4
const _MIN_DIST_WEAPON: int = 5
const _MIN_DIST_TREASURE_WEAPON: int = 3


# ============================================================================
# LIFECYCLE
# ============================================================================
func _ready() -> void:
        # Start with a valid maze even if generate() isn't called explicitly,
        # mirroring Maze::Maze() which calls generate() in the constructor.
        generate(level)


func _process(delta: float) -> void:
        # Accumula il tempo per le animazioni (flicker torce).
        _anim_time += delta
        # FIX (luci senza lanterne): ridisegna ogni frame per animare la
        # fiamma delle torce (flicker sin/cos in _draw_torch). Senza questo,
        # le PointLight2D si vedono ma le lanterne sono statiche.
        # Costo: 1 redraw/frame del maze statico (5-6 ms su GPU entry-level).
        queue_redraw()


## TASK 72 (portale SOPRA i muri, richiesta utente "non puoi usare uno
## z-index?"): callback opzionale che il controller registra per
## disegnare il portale magico ALLA FINE della passata del Maze (DOPO i
## muri e le decorazioni) — il vortice sta sopra ogni muro e non puo'
## MAI essere tagliato/coperto dalla roccia. E' sicuro perche' dal TASK 70
## il vortice (62px al massimo) entra interamente nella sua cella 64px:
## disegnarlo sopra i muri non fa sovrapporre nulla, toglie solo ogni
## possibilita' che un muro lo copra. Storia: Task 68 lo mise SOTTO i muri
## (allora lo sprite 84px sbordava sulle rocce), Task 70 lo rientro' nella
## cella — ora il z-order e' definitivamente sopra.
## La callback riceve il CanvasItem del Maze (self) come contesto di draw.
var portal_draw_callback: Callable = Callable()


func _draw() -> void:
        # Always redraw - the C++ Maze::render also draws every frame because
        # torches animate. For static mazes you can gate this on needs_redraw.
        _render_floor_gradient()
        # TASK 80 (luci lanterne): POZZE DI LUCE sul pavimento, subito dopo il
        # gradiente e PRIMA delle celle: muri/tesori/armi disegnati dopo
        # restano nitidi SOPRA la luce; le entita' (nodi separati) pure. E'
        # qui che il dungeon scuro diventa leggibile: ogni torcia e la
        # lanterna dell'eroe gettano luce calda sul pavimento.
        _draw_lantern_floor_pools()
        # Disegno a passate: prima TUTTE le celle non-muro (pavimento,
        # tesori, armi — nessuna sborda dalla propria cella), poi i muri
        # veri e propri, poi le decorazioni. Il portale va PER ULTIMO
        # (TASK 72: z-index sopra i muri, vedi portal_draw_callback).
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if _get_cell_type(c, r) != C.CellType.WALL:
                                _render_cell(c, r)
        # Le celle WALL dei muri di roccia MOBILI (Task 30) si disegnano come
        # pavimento (le lastre visibili sono nel MazeHazards) — passata 1.
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if _get_cell_type(c, r) == C.CellType.WALL \
                                        and dynamic_walls.has("%d,%d" % [c, r]):
                                _render_cell(c, r)
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if _get_cell_type(c, r) == C.CellType.WALL \
                                        and not dynamic_walls.has("%d,%d" % [c, r]):
                                _render_cell(c, r)
        # Decora alcune celle WALL con teschi, ragnatele, crepe
        # (vantaggio Godot: texture procedurali ad alta risoluzione)
        # TASK 80: PRIMA delle decorazioni, l'ALONE CALDO dei muri vicino
        # alle torce (la luce "bagna" la roccia; le fiamme restano sopra).
        _draw_lantern_wall_halos()
        _render_wall_decorations()
        # FIX (meccanica tunnel "Pac-Man"): deformazione a SEMILUNA del
        # muro di bordo sulle 4 aperture (richiesta utente: niente grafica
        # di grotta, solo la deformazione del muro stesso).
        _draw_tunnel_halfmoons()
        # TASK 72: portale magico PER ULTIMO, sopra muri e decorazioni —
        # mai piu' tagliato da un muro disegnato sopra (feedback utente
        # "il portale sta ancora sotto il muro perche' il muro e' disegnato
        # sopra... non puoi usare uno z-index?").
        if portal_draw_callback.is_valid():
                portal_draw_callback.call(self)


# Variabili per le luci delle torce (create una volta in generate)
var _torch_lights: Array = []
# Posizioni delle torce per disegnarle nel _render_wall_decorations
var _torch_positions: Array = []
# Tempo accumulato per le animazioni (flicker torce). In secondi.
var _anim_time: float = 0.0

# ============================================================================
# TASK 80 — LANTERNE: il dungeon torna scuro, la luce e' delle lanterne
# ============================================================================
## Posizioni (pixel, spazio MainGame = spazio Maze) dei player VIVI.
## Il MainGameController le aggiorna ogni frame in _update_playing: il Maze
## disegna sotto ciascun player una pozza di luce calda ("lanterna dell'eroe")
## cosi' il player scuro (elf) e i nemici scuri vicini restano leggibili per
## CONTRASTO senza schiarire il pavimento di tutto il dungeon.
var player_light_positions: Array = []

## TUTTE le posizioni torcia del livello (pixel, alla fiamma). Diversamente
## dalle PointLight2D (capped a 6 per performance) le POZZE BAKEATE sul
## pavimento coprono OGNI torcia: costo = 2 draw_texture_rect a torcia nella
## passata _draw() che il Maze gia' rifà ogni frame per il flicker.
var _all_torch_positions: Array = []

## Texture radiale bianca (alpha falloff quadratico, core pieno) condivisa
## da tutte le pozze/alone: il colore caldo passa via modulate al draw.
static var _lantern_pool_tex: Texture2D = null


## Texture pozza di luce 256x256: bianca con alpha 1 al centro che cade a 0
## al bordo (quadratica, leggero boost del core). Cache static UNICA per
## tutte le lanterne del gioco (un solo upload GPU a vita).
static func _get_lantern_pool_texture() -> Texture2D:
        if _lantern_pool_tex != null:
                return _lantern_pool_tex
        const POOL_SIZE: int = 256
        var img := Image.create(POOL_SIZE, POOL_SIZE, false, Image.FORMAT_RGBA8)
        var center := Vector2(POOL_SIZE / 2.0, POOL_SIZE / 2.0)
        var max_d: float = POOL_SIZE / 2.0
        for y in range(POOL_SIZE):
                for x in range(POOL_SIZE):
                        var d: float = Vector2(x, y).distance_to(center) / max_d
                        var a: float = clampf(1.0 - d, 0.0, 1.0)
                        a = clampf(a * a * 1.25, 0.0, 1.0)
                        img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
        _lantern_pool_tex = ImageTexture.create_from_image(img)
        return _lantern_pool_tex


## Disegna una pozza di luce (texture radiale) centrata in `center`, raggio
## `radius`, colore caldo `tint` con intensita' `alpha`. Mix blending: il
## pavimento sotto vira verso il caldo e si SCHIARISCE al centro.
func _draw_light_pool(tex: Texture2D, center: Vector2, radius: float,
                tint: Color, alpha: float) -> void:
        var col := Color(tint.r, tint.g, tint.b, clampf(alpha, 0.0, 1.0))
        var rect := Rect2(center.x - radius, center.y - radius,
                radius * 2.0, radius * 2.0)
        draw_texture_rect(tex, rect, false, col, false)


## TASK 80: pozze di luce sul PAVIMENTO (passata tra gradiente e celle, cosi'
## muri/sprite disegnati dopo restano nitidi sopra la luce):
##   - una pozza calda per OGNI torcia (~150px, flicker sincrono con la
##     fiamma: stessa famiglia sin() del _draw_torch);
##   - una pozza per ogni player vivo ("lanterna dell'eroe", ~130px): il
##     buio del dungeon resta, ma attorno all'eroe c'e' sempre luce.
func _draw_lantern_floor_pools() -> void:
        if not C.LANTERN_LIGHT_ENABLED:
                return
        var tex: Texture2D = _get_lantern_pool_texture()
        if tex == null:
                return
        for i in range(_all_torch_positions.size()):
                var pos: Vector2 = _all_torch_positions[i]
                var fl: float = 0.90 + 0.10 * sin(_anim_time * 17.0 + pos.x * 0.37)
                _draw_light_pool(tex, pos, 150.0, Color(1.0, 0.72, 0.40), 0.55 * fl)
        for i in range(player_light_positions.size()):
                var pos: Vector2 = player_light_positions[i]
                var fl: float = 0.94 + 0.06 * sin(_anim_time * 21.0 + pos.y * 0.21)
                _draw_light_pool(tex, pos, 130.0, Color(1.0, 0.82, 0.55), 0.50 * fl)


## TASK 80: alone caldo SOPRA i muri vicino alle torce (passata dopo i muri,
## prima delle decorazioni: la fiamma resta sopra tutto). Effetto "la luce
## della torcia bagna la roccia": mix sottile (alpha ~0.17) che riprende i
## toni caldi sui muri scuri restaurati, coordinato col flicker della pozza.
func _draw_lantern_wall_halos() -> void:
        if not C.LANTERN_LIGHT_ENABLED:
                return
        var tex: Texture2D = _get_lantern_pool_texture()
        if tex == null:
                return
        for i in range(_all_torch_positions.size()):
                var pos: Vector2 = _all_torch_positions[i]
                var fl: float = 0.90 + 0.10 * sin(_anim_time * 17.0 + pos.x * 0.37)
                _draw_light_pool(tex, pos, 95.0, Color(1.0, 0.74, 0.44), 0.17 * fl)


# ============================================================================
# DETERMINISTIC HASH HELPERS
# ============================================================================
# Hash deterministico 0..1 per cella + sale, mimico del cellHash del C++
# (usato per posizionare urne, crepe, muschio, ciottoli in modo stabile).
static func _cell_hash(c: int, r: int, salt: int = 0) -> float:
        var h: int = (c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)
        var uh: int = h if h >= 0 else -h
        # Mischia i bit per evitare pattern regolari (xor-shift + multiply).
        uh = (uh ^ (uh >> 13)) & 0xFFFFFFFF
        uh = (uh * 2654435761) & 0xFFFFFFFF
        uh = (uh ^ (uh >> 15)) & 0xFFFFFFFF
        return float(uh & 0xFFFF) / 65535.0


# Disegna un rettangolo w x h centrato in (cx, cy) ruotato di angle_deg.
# Helper usato per crepe dei muri e del pavimento (in C++ sf::RectangleShape::rotate).
func _draw_rotated_rect(cx: float, cy: float, w: float, h: float, angle_deg: float, color: Color) -> void:
        var a: float = deg_to_rad(angle_deg)
        var cos_a: float = cos(a)
        var sin_a: float = sin(a)
        var hw: float = w * 0.5
        var hh: float = h * 0.5
        # 4 angoli del rettangolo centrato in origine, poi ruotati e traslati.
        var corners := PackedVector2Array([
                Vector2(cx + (-hw * cos_a + hh * sin_a),  cy + (-hw * sin_a - hh * cos_a)),
                Vector2(cx + ( hw * cos_a + hh * sin_a),  cy + ( hw * sin_a - hh * cos_a)),
                Vector2(cx + ( hw * cos_a - hh * sin_a),  cy + ( hw * sin_a + hh * cos_a)),
                Vector2(cx + (-hw * cos_a - hh * sin_a),  cy + (-hw * sin_a + hh * cos_a)),
        ])
        draw_colored_polygon(corners, color)


# Renderizza decorazioni procedurali sulle pareti del dungeon.
# Usa un seed deterministico basato su (c,r,level) per posizionare in modo
# consistente teschi/ragnatele/creppe su certe celle WALL. Inoltre:
#   - Disegna il supporto fisico della torcia (handle + bracket + fiamma)
#     procedurale animato (1:1 con drawTorch del C++), non solo la texture.
#   - Posiziona urne decorative in ~2.5% delle celle EMPTY (1:1 con drawUrn C++).
func _render_wall_decorations() -> void:
        var skull_tex: Texture2D = null
        var cobweb_tex: Texture2D = null
        if EnvironmentArt:
                skull_tex = EnvironmentArt.get_skull_texture()
                cobweb_tex = EnvironmentArt.get_cobweb_texture()
        # Le urne decorative sono disegnate in _render_floor_decorations per
        # ogni cella EMPTY, insieme alle crepe/ciottoli del pavimento.
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        var cell_type: int = _get_cell_type(c, r)
                        var px: float = c * C.TILE_SIZE
                        var py: float = r * C.TILE_SIZE + C.UI_HEIGHT
                        var size: float = C.TILE_SIZE
                        # --- Urne decorative nelle celle EMPTY (~2.5%) ---
                        # 1:1 con Maze.cpp drawUrn: cellHash(c+5000, r+6000) <= 0.025.
                        # Le urne non bloccano il movimento ne' sono raccoglibili.
                        # FIX (tunnel): niente urne dentro le gallerie (sarebbero
                        # dentro la bocca di grotta, stonano e basta).
                        if cell_type == C.CellType.EMPTY:
                                if (c > 2 or r > 2) and not C.is_tunnel_cell(c, r):
                                        if _cell_hash(c, r, 5000) <= 0.025:
                                                var cx_u: float = px + size * 0.5
                                                var cy_u: float = py + size * 0.5
                                                _draw_urn(cx_u, cy_u, _cell_hash(c, r, 333))
                                continue
                        if cell_type != C.CellType.WALL:
                                continue
                        # TASK 30 (muri di roccia mobili): niente torce sopra le
                        # lastre che scorrono (la fiamma seguirebbe il muro e la
                        # PointLight2D resterebbe sospesa a vuoto sul passaggio).
                        if dynamic_walls.has("%d,%d" % [c, r]):
                                continue
                        # FIX (luci senza lanterne): l'utente vedeva le PointLight2D
                        # sui muri senza il disegno della torcia (era commentato).
                        # Disegnamo la torcia procedurale SOLO dove c'è una
                        # PointLight2D corrispondente, così le luci sono
                        # "giustificate" visivamente dalla lanterna.
                        # Le PointLight2D sono spawnate in _spawn_torch_lights()
                        # con hash_val in [14, 19) — stessa condizione qui.
                        var h: int = (c * 73856093) ^ (r * 19349663) ^ (level * 83492791)
                        var hash_val: int = abs(h) % 100
                        if hash_val >= 14 and hash_val < 19 and c > 1 and c < C.MAZE_COLS - 2:
                                var torch_x: float = px + size * 0.5
                                var torch_y: float = py + size * 0.35
                                _draw_torch(torch_x, torch_y, _anim_time)
                        # Skull/cobweb decorazioni rimangono disabilitate (muri puliti)
                        # var h: int = (c * 73856093) ^ (r * 19349663) ^ (level * 83492791)
                        # var hash_val: int = abs(h) % 100
                        # if hash_val < 8 and c > 2 and c < C.MAZE_COLS - 2 and r > 2 and r < C.MAZE_ROWS - 2:
                        #         if skull_tex:
                        #                 draw_texture_rect(skull_tex,
                        #                         Rect2(px + size * 0.15, py + size * 0.1,
                        #                               size * 0.7, size * 0.7), false)
                        # elif hash_val < 14 and (c <= 2 or c >= C.MAZE_COLS - 3 or r <= 2 or r >= C.MAZE_ROWS - 3):
                        #         if cobweb_tex:
                        #                 draw_texture_rect(cobweb_tex,
                        #                         Rect2(px, py, size * 0.8, size * 0.8), false)


# Disegna una torcia animata in posizione (x, y_base) dove y_base e' la base
# del bastone (la fiamma e' sopra). Port 1:1 della lambda drawTorch in
# Maze.cpp (righe 939-982). Disegna, nell'ordine:
#   1. Aura luminosa calda (2 cerchi semitrasparenti, r=22 e r=14)
#   2. Handle (rettangolo marrone 4x12 con outline scuro)
#   3. Bracket metallico (trapezio rovesciato a 4 punti, grigio ferro)
#   4. Fiamma a 3 strati animata con flicker sin/cos:
#      - Strato esterno rosso scuro (r=6+flicker)
#      - Strato medio arancione (r=4+flicker*0.6)
#      - Strato interno giallo-bianco (r=2)
func _draw_torch(x: float, y_base: float, t: float) -> void:
        # --- Aura luminosa calda (2 cerchi semitrasparenti) ---
        draw_circle(Vector2(x, y_base - 34.0), 22.0, Color(1.0, 0.71, 0.24, 0.14))
        draw_circle(Vector2(x, y_base - 26.0), 14.0, Color(1.0, 0.78, 0.31, 0.22))
        # --- TASK 54: sprite animato PixelLab (env/torch_sheet.png 4 frame) ---
        # Rollback: GameConstants.TORCH_SPRITE_ENABLED = false -> procedurale.
        if C.TORCH_SPRITE_ENABLED:
                var sheet: Texture2D = _get_torch_sheet()
                if sheet != null:
                        var frame_idx: int = int(t * 8.0 + x * 0.37) % 4
                        # frame 64x64, disegnato ~54px col fondo base a y_base+6
                        var s: float = 0.85
                        var src := Rect2(float(frame_idx) * 64.0, 0.0, 64.0, 64.0)
                        var w: float = 64.0 * s
                        var dst := Rect2(x - w * 0.5, y_base + 6.0 - w, w, w)
                        draw_texture_rect_region(sheet, dst, src, Color.WHITE, false)
                        return
        # --- Fallback procedurale (bastone + cestello + fiamma 3 strati) ---
        # --- Bastone della torcia (legno scuro 4x12) ---
        draw_rect(Rect2(x - 2.0, y_base - 4.0, 4.0, 12.0), Color(0.235, 0.118, 0.039), true)
        draw_rect(Rect2(x - 2.0, y_base - 4.0, 4.0, 12.0), Color(0.078, 0.039, 0.0), false, 0.8)
        # --- Cestello metallico (trapezio rovesciato a 4 punti) ---
        var bracket := PackedVector2Array([
                Vector2(x - 5.0, y_base - 4.0),
                Vector2(x + 5.0, y_base - 4.0),
                Vector2(x + 4.0, y_base - 10.0),
                Vector2(x - 4.0, y_base - 10.0),
        ])
        draw_colored_polygon(bracket, Color(0.314, 0.275, 0.235))
        # Outline del bracket (disegnato come linee chiuse sopra il fill).
        for i in range(4):
                var p1: Vector2 = bracket[i]
                var p2: Vector2 = bracket[(i + 1) % 4]
                draw_line(p1, p2, Color(0.157, 0.118, 0.078), 0.8)
        # --- Fiamma animata a 3 strati (flicker sin/cos come in C++) ---
        # sinf(time*18) e cosf(time*22) con fase x per ogni torcia.
        var flicker: float = sin(t * 18.0 + x) * 1.5
        var flicker2: float = cos(t * 22.0 + x * 0.7) * 1.0
        # Strato esterno (rosso scuro, r=6+flicker)
        var r3: float = 6.0 + flicker
        draw_circle(Vector2(x - flicker * 0.5, y_base - 24.0 + flicker2 * 0.3), r3,
                Color(0.706, 0.118, 0.039, 0.863))
        # Strato medio (arancione, r=4+flicker*0.6)
        var r2: float = 4.0 + flicker * 0.6
        draw_circle(Vector2(x - flicker * 0.3, y_base - 22.0 + flicker2 * 0.2), r2,
                Color(1.0, 0.549, 0.118, 0.941))
        # Strato interno (giallo-bianco, r=2)
        draw_circle(Vector2(x - 2.0, y_base - 19.0), 2.0, Color(1.0, 0.941, 0.706, 0.980))


# Cache statica dello sheet torcia PixelLab (TASK 54). Null se il PNG
# non esiste o il caricamento fallisce -> fallback procedurale.
static var _torch_sheet_cache: Texture2D = null
static var _torch_sheet_tried: bool = false

static func _get_torch_sheet() -> Texture2D:
        if _torch_sheet_tried:
                return _torch_sheet_cache
        _torch_sheet_tried = true
        var path := "res://assets/sprites/env/torch_sheet.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        _torch_sheet_cache = ImageTexture.create_from_image(img)
        return _torch_sheet_cache


# TASK 57: texture roccia PixelLab per i muri (grayscale normalizzata
# full-range, 128x128, opaca). Null se manca -> noise procedurale.
static var _rock_pixellab_cache: Image = null
static var _rock_pixellab_tried: bool = false

static func _load_pixellab_rock() -> Image:
        if _rock_pixellab_tried:
                return _rock_pixellab_cache
        _rock_pixellab_tried = true
        var path := "res://assets/sprites/env/rock_texture.png"
        var abs_path: String = ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(abs_path):
                var img := Image.new()
                if img.load(abs_path) == OK:
                        if img.get_size() != Vector2i(128, 128):
                                img.resize(128, 128, Image.INTERPOLATE_NEAREST)
                        _rock_pixellab_cache = img
        return _rock_pixellab_cache


# Disegna un'urna decorativa in (cx, cy). Port 1:1 di drawUrn in Maze.cpp
# (righe 1079-1173). 3 varianti colore determinate da `variant` (0..1):
#   - < 0.33: pietra grigia (decoro dorato)
#   - < 0.66: bronzo (decoro rosso scuro)
#   - >= 0.66: marmo scuro (decoro oro chiaro)
# Disegna: ombra a terra, base, corpo ovoidale (parte superiore + inferiore),
# bocca + bordo (cornicetta), highlight verticale, decoro centrale + simbolo
# rombo. Le urne sono puramente decorative (non bloccano ne' sono raccoglibili).
func _draw_urn(cx: float, cy: float, variant: float) -> void:
        # TASK 60a — urne PixelLab PNG-first (env/urn_{stone,bronze,marble}.png,
        # 128x128, stesse 3 palette procedurali del C++). Se il PNG manca
        # (rollback) si ricade sul disegno procedurale 1:1 col C++ qui sotto.
        if EnvironmentArt:
                var idx: int = 0
                if variant >= 0.33 and variant < 0.66:
                        idx = 1
                elif variant >= 0.66:
                        idx = 2
                var tex: Texture2D = EnvironmentArt.get_urn_texture(idx)
                if tex:
                        var h: float = 34.0
                        var w: float = h * float(tex.get_width()) / float(tex.get_height())
                        # Ombra a terra (stesso stile del fallback e del C++).
                        draw_circle(Vector2(cx, cy + 13.0), 11.0,
                                        Color(0.0, 0.0, 0.0, 0.45))
                        # Base dell'urna ancorata a cy+14 (coerente col vecchio
                        # appoggio del C++ che poggiava a cy+9 con l'ombra).
                        draw_texture_rect(tex,
                                        Rect2(cx - w * 0.5, cy + 14.0 - h, w, h),
                                        false)
                        return
        # ---- fallback procedurale (1:1 con drawUrn C++) ----
        # Palette in base alla variante (1:1 con drawUrn C++).
        var urn_col: Color
        var urn_dark: Color
        var urn_light: Color
        var urn_decor: Color
        if variant < 0.33:
                # Pietra grigia
                urn_col   = Color(0.431, 0.412, 0.392)
                urn_dark  = Color(0.275, 0.255, 0.235)
                urn_light = Color(0.667, 0.647, 0.627)
                urn_decor = Color(0.706, 0.549, 0.235)  # decoro dorato
        elif variant < 0.66:
                # Bronzo
                urn_col   = Color(0.471, 0.353, 0.196)
                urn_dark  = Color(0.275, 0.196, 0.098)
                urn_light = Color(0.706, 0.549, 0.314)
                urn_decor = Color(0.314, 0.118, 0.078)  # decoro rosso scuro
        else:
                # Marmo scuro
                urn_col   = Color(0.235, 0.216, 0.275)
                urn_dark  = Color(0.118, 0.098, 0.157)
                urn_light = Color(0.392, 0.373, 0.431)
                urn_decor = Color(0.863, 0.784, 0.314)  # decoro oro chiaro
        var outline_urn := Color(0.078, 0.059, 0.039)
        # --- Ombra a terra morbida ---
        draw_circle(Vector2(cx, cy + 8.0), 12.0, Color(0.0, 0.0, 0.0, 0.47))
        # --- Base dell'urna (rettangolo piu' largo in basso) ---
        draw_rect(Rect2(cx - 7.0, cy + 6.0, 14.0, 3.0), urn_dark, true)
        draw_rect(Rect2(cx - 7.0, cy + 6.0, 14.0, 3.0), outline_urn, false, 0.8)
        # --- Corpo ovoidale (parte superiore: largo al centro) ---
        var body_top := PackedVector2Array([
                Vector2(cx - 4.0, cy - 6.0),
                Vector2(cx + 4.0, cy - 6.0),
                Vector2(cx + 8.0, cy + 2.0),
                Vector2(cx - 8.0, cy + 2.0),
        ])
        draw_colored_polygon(body_top, urn_col)
        for i in range(4):
                draw_line(body_top[i], body_top[(i + 1) % 4], outline_urn, 1.0)
        # --- Parte inferiore del corpo (restringimento verso la base) ---
        var body_bot := PackedVector2Array([
                Vector2(cx - 8.0, cy + 2.0),
                Vector2(cx + 8.0, cy + 2.0),
                Vector2(cx + 5.0, cy + 6.0),
                Vector2(cx - 5.0, cy + 6.0),
        ])
        draw_colored_polygon(body_bot, urn_col)
        for i in range(4):
                draw_line(body_bot[i], body_bot[(i + 1) % 4], outline_urn, 1.0)
        # --- Highlight verticale (riflesso luce sul lato sinistro) ---
        draw_rect(Rect2(cx - 5.0, cy - 5.0, 1.5, 10.0), urn_light, true)
        # --- Bocca dell'urna (apertura superiore) + bordo (cornicetta) ---
        draw_rect(Rect2(cx - 3.0, cy - 8.0, 6.0, 2.0), urn_dark, true)
        draw_rect(Rect2(cx - 3.0, cy - 8.0, 6.0, 2.0), outline_urn, false, 0.5)
        draw_rect(Rect2(cx - 4.0, cy - 9.0, 8.0, 1.5), urn_light, true)
        draw_rect(Rect2(cx - 4.0, cy - 9.0, 8.0, 1.5), outline_urn, false, 0.5)
        # --- Decoro centrale (striscia orizzontale colorata) ---
        draw_rect(Rect2(cx - 5.0, cy - 1.0, 10.0, 1.5), urn_decor, true)
        # --- Simbolo rombo centrale ---
        var symbol := PackedVector2Array([
                Vector2(cx, cy - 1.0),
                Vector2(cx + 2.0, cy + 0.5),
                Vector2(cx, cy + 2.0),
                Vector2(cx - 2.0, cy + 0.5),
        ])
        draw_colored_polygon(symbol, urn_decor)


# Crea le PointLight2D per le torce una volta sola (chiamato da generate).
# Le luci sono figli del Maze node e seguono le posizioni delle torce.
# TASK 80: raccoglie TUTTE le torce del livello in _all_torch_positions
# (servono alle pozze bakeate di _draw_lantern_floor_pools: una per torcia)
# e distribuisce le 6 PointLight2D uniformemente sulla mappa invece di
# prendere le prime 6 in ordine di scansione (che si accatastavano in alto
# a sinistra). Raggio 80 -> 140: sui muri scuri restaurati la luce reale
# si vede e riprende la roccia attorno alla fiamma.
func _spawn_torch_lights() -> void:
        # Rimuovi le luci precedenti
        for light in _torch_lights:
                if is_instance_valid(light):
                        light.queue_free()
        _torch_lights.clear()
        _torch_positions.clear()
        _all_torch_positions.clear()
        # 1) Raccogli TUTTE le posizioni torcia del livello (hash [14,19),
        #    stessa condizione del disegno della torcia in
        #    _render_wall_decorations, escluse le lastre mobili Task 30).
        #    La posizione e' alla FIAMMA: centro cella, top cella (la fiamma
        #    _draw_torch vive a y_base-24 = top cella).
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if not is_wall(c, r):
                                continue
                        # TASK 30: niente torce sulle lastre di roccia mobili.
                        if dynamic_walls.has("%d,%d" % [c, r]):
                                continue
                        var h: int = (c * 73856093) ^ (r * 19349663) ^ (level * 83492791)
                        var hash_val: int = abs(h) % 100
                        if hash_val >= 14 and hash_val < 19 and c > 1 and c < C.MAZE_COLS - 2:
                                var px: float = c * C.TILE_SIZE + C.TILE_SIZE * 0.5
                                var py: float = r * C.TILE_SIZE + C.UI_HEIGHT
                                _all_torch_positions.append(Vector2(px, py))
        if not EffectsManager:
                return
        # 2) FIX (performance, invariato): massimo 6 PointLight2D per livello.
        #    Prima creava ~44 luci (5% di 880 celle WALL) → lag estremo su
        #    GPU entry-level. 6 luci + le pozze bakeate di TASK 80 (zero costo
        #    GPU: 2 draw_texture_rect a torcia nella passata esistente)
        #    danno atmosfera e visibilità senza lag.
        var max_lights: int = 6
        var n_torches: int = _all_torch_positions.size()
        if n_torches == 0:
                return
        for i in range(mini(max_lights, n_torches)):
                # Distribuzione uniforme sull'ordine di scansione (c-major:
                # sinistra->destra, alto->basso) = le 6 luci coprono tutta
                # la mappa invece di ammassarsi nelle prime celle.
                var idx: int = int(float(i) * float(n_torches) / float(mini(max_lights, n_torches)))
                idx = mini(idx, n_torches - 1)
                var pos: Vector2 = _all_torch_positions[idx]
                var light: PointLight2D = EffectsManager.create_light(
                                pos,
                                Color(1.0, 0.7, 0.3, 1.0),
                                1.2,  # energy
                                140.0  # radius (TASK 80: 80 -> 140)
                        )
                add_child(light)
                _torch_lights.append(light)
                _torch_positions.append(pos)


# ============================================================================
# GENERATION  (port of Maze::generate)
# ============================================================================
## Regenerate the maze for `lvl`. Mirrors Maze::generate(level) line-by-line.
var affinity_char_types: Array = []  ## TASK 61: archetipi dei player; selettore pool armi nel labirinto


func generate(lvl: int = 1) -> void:
        level = lvl
        _init_grid()

        # 1) Start with all WALL.
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        _set_cell_type(c, r, C.CellType.WALL)

                # 2) Iterative DFS (recursive backtracker). Dig 2 cells at a time.

                # 3) Open ~15 extra walls with exactly 2 wall-neighbors -> creates loops.

                # 4) Collect empty cells and shuffle them so treasure/weapon placement
                #    is uniformly random but with minimum-distance constraints.

                # 5) Place treasures (8, min Manhattan distance 4 from each other).

                # 6) Place weapons (5, min distance 5 from each other, 3 from treasures).

                # 7) Pick the palette for this level.
        _dfs_carve()

        # 3) Open ~15 extra walls with exactly 2 wall-neighbors -> creates loops.
        for _i in range(_NUM_EXTRA_OPENINGS):
                var c: int = 1 + (randi() % (C.MAZE_COLS - 2))
                var r: int = 1 + (randi() % (C.MAZE_ROWS - 2))
                if _get_cell_type(c, r) == C.CellType.WALL and _count_neighbor_walls(c, r) == 2:
                        _set_cell_type(c, r, C.CellType.EMPTY)

        # FIX (muro destro invisibile + doppio muro, definitivo): con 30
        # colonne il bordo destro (col 29) è l'ultima colonna VISIBLE su
        # schermo (30*64 = 1920 esatto). La DFS con passo 2 non scava MAI la
        # colonna 28 (pari: non ci sono stanze a colonna 29), quindi senza
        # questo passaggio resterebbe SEMPRE muro e, sommata al bordo (29),
        # formerebbe il doppio muro di 128px sull'intero lato destro.
        # FIX: apriamo la colonna 28 SOLO nelle righe in cui la colonna 27 è
        # già aperta. Risultato: bordo destro SINGOLO e visibile ovunque, con
        # il pattern del maze che sfuma naturalmente nel bordo (corridoi che
        # terminano contro il muro, blocchi di muro che si fondono col bordo
        # come nel C++ originale 21x19).
        for r in range(1, C.MAZE_ROWS - 1):
                if _get_cell_type(C.MAZE_COLS - 3, r) != C.CellType.WALL:
                        _set_cell_type(C.MAZE_COLS - 2, r, C.CellType.EMPTY)

        # FIX (meccanica tunnel "Pac-Man"): scava le 4 gallerie nel muro di
        # bordo. Ogni galleria = cella di bordo aperta + corridoio di accesso
        # (garantito connesso al resto del maze perche' le celle di accesso
        # vicine sono odd-odd, che la DFS scava SEMPRE: (15,1), (15,13),
        # (1,7), (27,7)). Chi entra in una galleria riemerge dal lato opposto
        # (wrap gestito da GameConstants.tunnel_wrap + is_wall sulle celle
        # virtuali). I tesori/armi NON finiscono nelle gallerie: il placement
        # pesca solo celle interne (righe/colonne 1..N-2).
        # FIX (dimensione fori): tutte le gallerie sono larghe 1 cella (64px)
        # anche in alto/basso (colonna 15), cosi' i 4 fori sono IDENTICI.
        # - Alto al centro (colonna 15): imbocco riga 0 + corridoio riga 1
        #   ((15,1) e' odd-odd, sempre gia' aperta).
        # - Basso al centro (colonna 15): imbocco riga 14 + corridoio riga 13.
        # - Sinistra al centro (riga 7): imbocco col 0 + corridoio col 1.
        # - Destra al centro (riga 7): imbocco col 29 + corridoio col 28
        #   (col 27 e' gia' aperta: odd-odd sempre scavata dalla DFS).
        for tc in C.TUNNEL_COLS_TOP_BOTTOM:
                _set_cell_type(tc, 0, C.CellType.EMPTY)                       # imbocco alto
                _set_cell_type(tc, 1, C.CellType.EMPTY)                       # corridoio alto
                _set_cell_type(tc, C.MAZE_ROWS - 1, C.CellType.EMPTY)  # imbocco basso
                _set_cell_type(tc, C.MAZE_ROWS - 2, C.CellType.EMPTY)  # corridoio basso
        _set_cell_type(0, C.TUNNEL_ROW_SIDES, C.CellType.EMPTY)                # imbocco sinistra
        _set_cell_type(1, C.TUNNEL_ROW_SIDES, C.CellType.EMPTY)                # corridoio sinistra
        _set_cell_type(C.MAZE_COLS - 1, C.TUNNEL_ROW_SIDES, C.CellType.EMPTY)  # imbocco destra
        _set_cell_type(C.MAZE_COLS - 2, C.TUNNEL_ROW_SIDES, C.CellType.EMPTY)  # corridoio destra

                # 4) Collect empty cells and shuffle them so treasure/weapon placement
                #    is uniformly random but with minimum-distance constraints.

                # 5) Place treasures (8, min Manhattan distance 4 from each other).

                # 6) Place weapons (5, min distance 5 from each other, 3 from treasures).

                # 7) Pick the palette for this level.
        var empty_cells: Array = _collect_empty_cells()
        empty_cells.shuffle()

        # 5) Place treasures (8, min Manhattan distance 4 from each other).
        var placed_items: Array = []  # all placed (treasures + weapons)
        var placed_treasures: Array = []  # only treasures (for T-W distance)
        var treasures_placed: int = 0
        for cell in empty_cells:
                if treasures_placed >= _TREASURES_PER_LEVEL:
                        break
                if _is_far_enough(cell, placed_items, _MIN_DIST_TREASURE):
                        var cc: int = cell.x
                        var rr: int = cell.y
                        _set_cell_type(cc, rr, C.CellType.TREASURE)
                        _set_cell_treasure(cc, rr, randi() % 5)  # TRES_CROWN..TRES_RUBY
                        placed_items.append(cell)
                        placed_treasures.append(cell)
                        treasures_placed += 1

                # 6) Place weapons (5, min distance 5 from each other, 3 from treasures).

                # 7) Pick the palette for this level.
        var weapons_placed: int = 0
        for cell in empty_cells:
                if weapons_placed >= _WEAPONS_PER_LEVEL:
                        break
                if _get_cell_type(cell.x, cell.y) != C.CellType.EMPTY:
                        continue
                if not _is_far_enough(cell, placed_treasures, _MIN_DIST_TREASURE_WEAPON):
                        continue
                if _is_far_enough(cell, placed_items, _MIN_DIST_WEAPON):
                        _set_cell_type(cell.x, cell.y, C.CellType.WEAPON)
                        # TASK 61 — le armi nel labirinto seguono l'affinita'
                        # degli archetipi dei player (umani -> armi da fuoco,
                        # non-umani -> elementali del proprio pool).
                        _set_cell_weapon(cell.x, cell.y, C.make_random_weapon(affinity_char_types))
                        placed_items.append(cell)
                        weapons_placed += 1

                # 7) Pick the palette for this level.
        var pal_idx: int = C.get_palette_index(level)
        var pal: Dictionary = _PALETTES[pal_idx]
        wall_color = pal["wall"]
        bg_color = pal["bg"]
        # FIX (muri rocciosi procedurali): rigenera/aggiorna la cached rock
        # texture per il livello corrente. Costo una tantum (~5ms) per palette
        # mai usata; riutilizzo dalla cache se la palette è già stata vista.
        _rock_tex = _generate_rock_texture(pal_idx, wall_color)

        # Crea le PointLight2D per le torce sulle pareti (max 6 per performance).
        _spawn_torch_lights()

        needs_redraw = true
        maze_generated.emit(level)
        queue_redraw()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
## Initialize the grid to all WALL with default Cell fields.
func _init_grid() -> void:
        _grid.clear()
        _grid.resize(C.MAZE_COLS * C.MAZE_ROWS)
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        _grid[_idx(c, r)] = {
                                "type": C.CellType.WALL,
                                "treasure": C.TreasureType.CROWN,
                                "weapon": C.make_weapon(C.WeaponType.PISTOL),
                        }


# ============================================================================
# FIX (continue = sessione ESATTA): serializzazione / ripristino della griglia
# ============================================================================
## Serializza lo stato COMPLETO della griglia (tipo cella, tipo tesoro, arma
## a terra) in un Dictionary serializzabile (Array piatti). Usato dal
## MainGameController per lo snapshot della sessione al momento della morte:
## al continue il labirinto viene ripristinato CELLA PER CELLA (tesori gia'
## raccolti che restano raccolti, muri rotti dal martello che restano rotti,
## armi a terra residue al loro posto) invece di essere rigenerato random.
func serialize_state() -> Dictionary:
        var types: Array = []
        types.resize(_grid.size())
        var tres: Array = []
        tres.resize(_grid.size())
        var wpns: Array = []
        wpns.resize(_grid.size())
        for i in range(_grid.size()):
                var cell: Dictionary = _grid[i]
                types[i] = int(cell.get("type", C.CellType.WALL))
                tres[i] = int(cell.get("treasure", 0))
                var w: Dictionary = cell.get("weapon", {})
                if w.is_empty():
                        wpns[i] = {}
                else:
                        wpns[i] = {
                                "type": int(w.get("type", 0)),
                                "power": int(w.get("power", 1)),
                                "ammo": int(w.get("ammo", 0)),
                        }
        return {"level": level, "types": types, "treasures": tres, "weapons": wpns}


## Ripristina la griglia da uno snapshot di serialize_state() e riapplica
## palette / texture rocciose / luci delle torce / redraw (le stesse code di
## generate(), SENZA rigenerare nulla: il layout resta identico a quando il
## player e' morto).
func restore_state(snap_data: Dictionary) -> void:
        var types: Array = snap_data.get("types", [])
        var tres: Array = snap_data.get("treasures", [])
        var wpns: Array = snap_data.get("weapons", [])
        var expected: int = C.MAZE_COLS * C.MAZE_ROWS
        if types.size() != expected or tres.size() != expected or wpns.size() != expected:
                push_warning("[Maze] restore_state: snapshot malformato (size "
                                + str(types.size()) + "), rigenero il livello.")
                generate(int(snap_data.get("level", 1)))
                return
        level = int(snap_data.get("level", 1))
        _init_grid()
        for i in range(expected):
                var cell: Dictionary = _grid[i]
                cell["type"] = int(types[i])
                cell["treasure"] = int(tres[i])
                var w: Dictionary = wpns[i]
                if w is Dictionary and not (w as Dictionary).is_empty():
                        cell["weapon"] = (w as Dictionary).duplicate()
        # 7) Palette / texture rocciose / luci: identico a generate().
        var pal_idx: int = C.get_palette_index(level)
        var pal: Dictionary = _PALETTES[pal_idx]
        wall_color = pal["wall"]
        bg_color = pal["bg"]
        _rock_tex = _generate_rock_texture(pal_idx, wall_color)
        _spawn_torch_lights()
        needs_redraw = true
        maze_generated.emit(level)
        queue_redraw()


## Iterative DFS maze carving (step 2 of generate). Matches the C++ stack
## loop exactly. Note: the start cell is (1, 1) and the deltas are step 2.
func _dfs_carve() -> void:
        # Directions: up, right, down, left, step 2 (preserves walls on parity).
        var dc: Array = [0, 2, 0, -2]
        var dr: Array = [-2, 0, 2, 0]

        _set_cell_type(1, 1, C.CellType.EMPTY)
        var stack: Array = [Vector2i(1, 1)]

        while not stack.is_empty():
                var curr: Vector2i = stack.back()
                var neighbors: Array = []
                for i in range(4):
                        var nc: int = curr.x + dc[i]
                        var nr: int = curr.y + dr[i]
                        # Out-of-bounds and already-visited cells are skipped. The
                        # bounds check matches the C++ condition: 0 < nc < COLS-1
                        # and 0 < nr < ROWS-1 (the border ring stays as walls).
                        var in_bounds: bool = (
                                nc > 0 and nc < C.MAZE_COLS - 1 and nr > 0 and nr < C.MAZE_ROWS - 1
                        )
                        if in_bounds and _get_cell_type(nc, nr) == C.CellType.WALL:
                                neighbors.append(i)

                                # Carve the wall halfway between curr and the destination.

                                # Carve the destination cell.
                if not neighbors.is_empty():
                        var dir: int = neighbors[randi() % neighbors.size()]
                        # Carve the wall halfway between curr and the destination.
                        _set_cell_type(curr.x + dc[dir] / 2, curr.y + dr[dir] / 2, C.CellType.EMPTY)
                        # Carve the destination cell.
                        _set_cell_type(curr.x + dc[dir], curr.y + dr[dir], C.CellType.EMPTY)
                        stack.append(Vector2i(curr.x + dc[dir], curr.y + dr[dir]))
                else:
                        stack.pop_back()


## Counts the WALL neighbors of (c, r). Bounds are NOT checked here; the
## caller is expected to call this only on internal cells (matches the C++
## comment "Non effettua controlli sui bordi").
func _count_neighbor_walls(c: int, r: int) -> int:
        var count: int = 0
        if _get_cell_type(c - 1, r) == C.CellType.WALL:
                count += 1
        if _get_cell_type(c + 1, r) == C.CellType.WALL:
                count += 1
        if _get_cell_type(c, r - 1) == C.CellType.WALL:
                count += 1
        if _get_cell_type(c, r + 1) == C.CellType.WALL:
                count += 1
        return count


## Collects all EMPTY cells as Vector2i, excluding the border ring (matches
## the C++ range `c in [1, COLS-2], r in [1, ROWS-2]`).
func _collect_empty_cells() -> Array:
        var out: Array = []
        for c in range(1, C.MAZE_COLS - 1):
                for r in range(1, C.MAZE_ROWS - 1):
                        if _get_cell_type(c, r) == C.CellType.EMPTY:
                                out.append(Vector2i(c, r))
        return out


## Returns true if `candidate` is at least `min_dist` (Manhattan) away from
## every position in `positions`. Used by the placement step.
static func _is_far_enough(candidate: Vector2i, positions: Array, min_dist: int) -> bool:
        for p in positions:
                if abs(p.x - candidate.x) + abs(p.y - candidate.y) < min_dist:
                        return false
        return true


# ============================================================================
# PUBLIC QUERY / MUTATION API  (mirror of Maze.h public interface)
# ============================================================================
## True if the cell is a WALL or out of grid bounds. Used by player, enemy
## and projectile code for collision detection.
## FIX (tunnel Pac-Man): le celle VIRTUALI appena fuori griglia che
## continuano le gallerie sono calpestabili (chi le attraversa riemerge dal
## lato opposto). Tutto il resto fuori griglia resta muro, come prima.
func is_wall(col: int, row: int) -> bool:
        if col < 0 or col >= C.MAZE_COLS or row < 0 or row >= C.MAZE_ROWS:
                return not C.is_tunnel_virtual_cell(col, row)
        # TASK 30 (muri di roccia mobili): la cella e' governata dal registro
        # dinamico — chiusa = muro pieno, aperta = passaggio libero. Il tipo
        # statico resta WALL (il Mjolnir puo' comunque spezzare il muro e il
        # MazeHazards sgretola le lastre di conseguenza).
        var dyn_key := "%d,%d" % [col, row]
        if dynamic_walls.has(dyn_key):
                return dynamic_walls[dyn_key]
        return _get_cell_type(col, row) == C.CellType.WALL


## Returns the CellType of a cell. Out-of-bounds is treated as WALL.
func get_cell_type(col: int, row: int) -> int:
        if col < 0 or col >= C.MAZE_COLS or row < 0 or row >= C.MAZE_ROWS:
                return C.CellType.WALL
        return _get_cell_type(col, row)


## Collect the treasure at (col, row). The cell becomes EMPTY. Emits
## `treasure_collected` and, when the count hits 0, `all_treasures_collected`.
func collect_treasure(col: int, row: int) -> void:
        if get_cell_type(col, row) != C.CellType.TREASURE:
                push_warning("Maze.collect_treasure called on non-treasure cell (%d,%d)" % [col, row])
                return
        var tres_type: int = _get_cell_treasure(col, row)
        _set_cell_type(col, row, C.CellType.EMPTY)
        needs_redraw = true
        queue_redraw()
        treasure_collected.emit(col, row, tres_type)
        if get_remaining_treasures() == 0:
                all_treasures_collected.emit()


## FIX (martello di Thor): rompe il muro INTERNO alla cella (col, row),
## trasformandolo in pavimento calpestabile. Usato dal MainGameController
## quando il martello lanciato colpisce un muro. La cella diventa EMPTY:
## player, nemici e BFS la usano subito come passaggio-scorciatoia (la
## griglia e' letta in tempo reale da is_wall / BFS.find_path).
## Il chiamante filtra gia' i muri di BORDO (indistruttibili per progetto:
## romperli creerebbe un ulteriore effetto Pac-Man oltre alle gallerie).
func break_wall(col: int, row: int) -> bool:
        if col < 0 or col >= C.MAZE_COLS or row < 0 or row >= C.MAZE_ROWS:
                return false
        if _get_cell_type(col, row) != C.CellType.WALL:
                return false
        _set_cell_type(col, row, C.CellType.EMPTY)
        needs_redraw = true
        queue_redraw()
        return true


# FIX (scarpe alate bloccano livello): cerca e rimuove la cella TREASURE
# più vicina alla posizione data. Usato quando il player raccoglie un
# collectible TREASURE che non è sopra una cella TREASURE del maze.
func remove_nearest_treasure(from_col: int, from_row: int) -> void:
        var best_c: int = -1
        var best_r: int = -1
        var best_dist: int = 999999
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if _get_cell_type(c, r) == C.CellType.TREASURE:
                                var d: int = abs(c - from_col) + abs(r - from_row)
                                if d < best_dist:
                                        best_dist = d
                                        best_c = c
                                        best_r = r
        if best_c >= 0:
                collect_treasure(best_c, best_r)


## Collect the weapon at (col, row). Returns the weapon Dictionary and
## sets the cell to EMPTY. Emits `weapon_collected`.
func collect_weapon(col: int, row: int) -> Dictionary:
        if get_cell_type(col, row) != C.CellType.WEAPON:
                push_warning("Maze.collect_weapon called on non-weapon cell (%d,%d)" % [col, row])
                return C.make_weapon(C.WeaponType.PISTOL)
        var w: Dictionary = _get_cell_weapon(col, row)
        _set_cell_type(col, row, C.CellType.EMPTY)
        needs_redraw = true
        queue_redraw()
        weapon_collected.emit(col, row, w.get("type", C.WeaponType.PISTOL))
        return w


## Counts the TREASURE cells remaining in the maze. When this hits 0 the
## Game class opens the exit door / starts the boss fight.
func get_remaining_treasures() -> int:
        var count: int = 0
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if _get_cell_type(c, r) == C.CellType.TREASURE:
                                count += 1
        return count


## Returns the weapon Dictionary of a cell (read-only - use collect_weapon
## to mutate). Returns a default pistol for non-weapon cells.
func get_cell_weapon(col: int, row: int) -> Dictionary:
        if get_cell_type(col, row) != C.CellType.WEAPON:
                return C.make_weapon(C.WeaponType.PISTOL)
        return _get_cell_weapon(col, row)


# ============================================================================
# GRID ACCESSORS (private)
# ============================================================================
## Flat index for cell (c, r). Used to keep O(1) lookup.
static func _idx(c: int, r: int) -> int:
        return c * C.MAZE_ROWS + r


func _get_cell_type(c: int, r: int) -> int:
        return _grid[_idx(c, r)]["type"]


func _set_cell_type(c: int, r: int, t: int) -> void:
        _grid[_idx(c, r)]["type"] = t


func _get_cell_treasure(c: int, r: int) -> int:
        return _grid[_idx(c, r)]["treasure"]


func _set_cell_treasure(c: int, r: int, t: int) -> void:
        _grid[_idx(c, r)]["treasure"] = t


func _get_cell_weapon(c: int, r: int) -> Dictionary:
        return _grid[_idx(c, r)]["weapon"]


func _set_cell_weapon(c: int, r: int, w: Dictionary) -> void:
        _grid[_idx(c, r)]["weapon"] = w


# ============================================================================
# RENDERING  (port of Maze::render - simplified but structurally faithful)
# ============================================================================
## Draws a smooth radial floor gradient covering the whole maze area, below
## the UI bar. This matches the C++ `floorGrad` VertexArray approach (the
## gradient eliminates the visible seams of per-tile floor fills).
func _render_floor_gradient() -> void:
        var center_c: float = C.MAZE_COLS / 2.0
        var center_r: float = C.MAZE_ROWS / 2.0
        var total_w: float = C.MAZE_COLS * C.TILE_SIZE
        var total_h: float = C.MAZE_ROWS * C.TILE_SIZE
        # 9x9 vertices = 8x8 quads, same segmentation as the C++ version.
        const SEG_X: int = 9
        const SEG_Y: int = 9
        var step_x: float = total_w / (SEG_X - 1)
        var step_y: float = total_h / (SEG_Y - 1)

        # We draw the gradient with a series of small colored rects. Godot's
        # draw_rect does not interpolate vertex colors across a quad like SFML's
        # VertexArray does, so we approximate by computing the color at the
        # CENTER of each quad. The result is a slightly chunkier gradient; for
        # a pixel-perfect match a CanvasItem mesh with vertex colors could be
        # used instead.
        for sy in range(SEG_Y - 1):
                for sx in range(SEG_X - 1):
                        var x0: float = sx * step_x
                        var y0: float = C.UI_HEIGHT + sy * step_y
                        var cell_cx: float = (sx + 0.5) * step_x / C.TILE_SIZE
                        var cell_cy: float = (sy + 0.5) * step_y / C.TILE_SIZE
                        var dx: float = (cell_cx - center_c) / center_c
                        var dy: float = (cell_cy - center_r) / center_r
                        var dist: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
                        var brightness: float = 24.0 - dist * 18.0
                        var col := Color(
                                clampf(bg_color.r + brightness / 255.0, 0.0, 1.0),
                                clampf(bg_color.g + brightness * 0.7 / 255.0, 0.0, 1.0),
                                clampf(bg_color.b + brightness * 0.4 / 255.0, 0.0, 1.0),
                        )
                        draw_rect(Rect2(x0, y0, step_x + 1, step_y + 1), col, true)


## Renders a single cell. WALL -> 5-band rocky gradient + crepe/muschio;
## TREASURE -> pedestal + simple icon; WEAPON -> colored square (full Weapon
## rendering belongs to a Weapon.gd scene, not the maze); EMPTY -> crepe,
## ciottoli e macchie di terriccio sopra il gradiente.
func _render_cell(c: int, r: int) -> void:
        var cell_type: int = _get_cell_type(c, r)
        var px: float = c * C.TILE_SIZE
        var py: float = r * C.TILE_SIZE + C.UI_HEIGHT
        var size: float = C.TILE_SIZE

        match cell_type:
                C.CellType.WALL:
                        # TASK 30 (muri di roccia mobili): la cella del muro che
                        # si apre/chiude si disegna come PAVIMENTO — le due lastre
                        # di roccia del MazeHazards sono la parete visibile, cosi'
                        # da aperta si vede davvero la scorciatoia (e le lastre
                        # ritratte spuntano dai muri adiacenti).
                        if dynamic_walls.has("%d,%d" % [c, r]):
                                _render_floor_decorations(c, r, px, py, size)
                        else:
                                _render_wall_cell(c, r, px, py, size)
                C.CellType.TREASURE:
                        _render_treasure_cell(px, py, size, _get_cell_treasure(c, r))
                C.CellType.WEAPON:
                        _render_weapon_cell(px, py, size, _get_cell_weapon(c, r))
                C.CellType.EMPTY, _:
                        _render_floor_decorations(c, r, px, py, size)


## Draws a WALL cell as a rocky procedural texture, mirroring the C++
## "rocky dungeon" effect: texture rocciosa tinteggiata con wall_color del
## livello. TASK 75 (feedback utente: "il muro aveva in precedenza, quando
## aveva 'gli angoli', il pattern dello screen — ripristinare quello stile
## SENZA usare gli angoli"): RIPRISTINATA la texture roccia PixelLab del
## Task 57 (massi organici irregolari con contorni scuri — quella dello
## screen) e RIMOSSI i bevel per-cellula del Task 73 (highlight NW + ombra
## SE + outline perimetrale su ogni cella): la superficie del muro e'
## puramente il pattern organico della texture, senza griglia di giunzioni
## e senza angoli. Crepe sottili (~10%) e muschio raro (~3%) invariati
## (port 1:1 del C++). La texture e' cached static per palette (8 max, mai
## rigenerata per lo stesso livello). Rollback texture uniforme Task 72:
## git show 6af8724:godot/assets/sprites/env/rock_texture.png.
func _render_wall_cell(c: int, r: int, px: float, py: float, size: float) -> void:
        # FIX (muri rocciosi procedurali): sostituisce le 5 draw_rect sovrapposte
        # (sintomo "rettangoli sfumati") con una draw_texture_rect_region che
        # blitta una porzione 64x64 della texture cached 128x128. La porzione
        # e' selezionata deterministicamente per cella -> niente tiling visibile.
        if _rock_tex != null:
                var h: int = abs((c * 73856093) ^ (r * 19349663) ^ (level * 83492791))
                var ox: float = float((h % 3) * 32)
                var oy: float = float(((h / 3) % 3) * 32)
                var src_rect := Rect2(ox, oy, float(C.TILE_SIZE), float(C.TILE_SIZE))
                var dst_rect := Rect2(px, py, size, size)
                draw_texture_rect_region(_rock_tex, dst_rect, src_rect, Color.WHITE, false, false)
        else:
                draw_rect(Rect2(px, py, size, size), wall_color, true)
        # TASK 75: NESSUN bevel/outline per-cellula (highlight NW, ombra SE e
        # bordo del blocco rimossi): il muro mostra SOLO il pattern organico
        # della texture Task 57 — le celle adiacenti si fondono in una massa
        # di roccia continua come nello screen di riferimento dell'utente.
        # --- Crepa rara (~10% delle celle muro, cellHash > 0.90) ---
        # Sottile rettangolo 1.2x6 ruotato nero semi-trasparente, 1:1 con C++.
        if _cell_hash(c + 99, r + 17) > 0.90:
                var h1: float = _cell_hash(c * 5 + 31, r * 7 + 19)
                var crack_cx: float = px + 8.0 + h1 * (size - 16.0)
                var crack_cy: float = py + 18.0
                var crack_ang: float = (h1 - 0.5) * 60.0
                _draw_rotated_rect(crack_cx, crack_cy, 1.2, 6.0, crack_ang,
                        Color(0.02, 0.02, 0.02, 0.51))
        # --- Muschio verde molto raro (~3%, cellHash > 0.97) ---
        # Piccolo cerchio verde alla base del muro (effetto umidita').
        if _cell_hash(c + 555, r + 333) > 0.97:
                var mx: float = px + 6.0 + _cell_hash(c, r) * (size - 12.0)
                var my: float = py + size - 6.0
                draw_circle(Vector2(mx, my), 2.5, Color(0.196, 0.353, 0.157, 0.78))


## Disegna le micro-decorazioni del pavimento per una cella EMPTY:
## crepe sottili (1-2 per cella), ciottoli (1-2 per cella) e macchie di
## terriccio (~12% delle celle). Port 1:1 di Maze.cpp righe 462-510.
## Le posizioni sono deterministiche (_cell_hash) per stabilita' tra frame.
func _render_floor_decorations(c: int, r: int, px: float, py: float, size: float) -> void:
        # --- Piccole crepe di terra (terriccio seccato): 1-2 per cella ---
        var num_cracks: int = 1 + int(_cell_hash(c + 50, r + 25) * 2.0)
        for i in range(num_cracks):
                var h1: float = _cell_hash(c * 17 + i + 100, r * 3 + i + 50)
                var h2: float = _cell_hash(c * 7 + i + 200, r * 13 + i + 70)
                var fcx: float = px + 6.0 + h1 * (size - 12.0)
                var fcy: float = py + 6.0 + h2 * (size - 12.0)
                var fang: float = (h1 - 0.5) * 40.0
                var flen: float = 5.0 + h2 * 4.0
                _draw_rotated_rect(fcx, fcy, 0.8, flen, fang,
                        Color(0.059, 0.031, 0.016, 0.55))
        # --- Piccoli sassolini sparsi (~1-2 per cella) ---
        var num_pebbles: int = 1 + int(_cell_hash(c + 200, r + 100) * 2.0)
        for i in range(num_pebbles):
                var h1: float = _cell_hash(c * 17 + i + 100, r * 3 + i + 50)
                var h2: float = _cell_hash(c * 7 + i + 200, r * 13 + i + 70)
                var h3: float = _cell_hash(c * 23 + i + 1,  r * 11 + i + 13)
                var pbx: float = px + 4.0 + h1 * (size - 8.0)
                var pby: float = py + 4.0 + h2 * (size - 8.0)
                var pbr: float = 1.2 + h3 * 1.2
                var pr: float = 0.373 + h3 * 0.118  # ~95..125
                var pg: float = 0.314 + h3 * 0.098  # ~80..105
                var pb: float = 0.235 + h3 * 0.071  # ~60..78
                draw_circle(Vector2(pbx, pby), pbr, Color(pr, pg, pb, 1.0))
        # --- Macchie di terra piu' scura (~12% delle celle) ---
        if _cell_hash(c + 700, r + 350) > 0.88:
                var h1: float = _cell_hash(c + 800, r + 400)
                var h2: float = _cell_hash(c + 900, r + 500)
                var sx: float = px + 8.0 + h1 * (size - 24.0)
                var sy: float = py + 8.0 + h2 * (size - 24.0)
                var sr: float = 3.0 + h1 * 2.0
                draw_circle(Vector2(sx, sy), sr, Color(0.059, 0.031, 0.016, 0.51))


## Draws a treasure cell: small stone pedestal + colored gem marker that
## varies by TreasureType. The C++ version draws full sprite art with
## primitives; we render a simpler version that's still distinct per type.
# Cache static per le texture dei tesori (evita Image.load() ogni frame nel maze).
# FIX (quadrati bianchi): Image.load() + ImageTexture.create_from_image() ogni
# frame per ogni cella tesoro causa lag e potenziali quadrati bianchi se
# l'Image non è pronto. Cachiamo le texture.
static var _maze_treasure_cache: Dictionary = {}

func _render_treasure_cell(px: float, py: float, size: float, tres_type: int) -> void:
        # FIX (tesori troppo piccoli nel maze): usa PNG AI dedicati
        # invece di texture procedurali EnvironmentArt, e disegna più grande.
        var tex_path: String = ""
        match tres_type:
                C.TreasureType.CROWN: tex_path = "res://assets/sprites/treasures/treasure_crown.png"
                C.TreasureType.GOLD: tex_path = "res://assets/sprites/treasures/treasure_gold.png"
                C.TreasureType.CHEST: tex_path = "res://assets/sprites/treasures/treasure_chest.png"
                C.TreasureType.GEM: tex_path = "res://assets/sprites/treasures/treasure_gem.png"
                C.TreasureType.RUBY: tex_path = "res://assets/sprites/treasures/treasure_ruby.png"
        if not tex_path.is_empty():
                var tex: Texture2D = null
                if _maze_treasure_cache.has(tex_path):
                        tex = _maze_treasure_cache[tex_path]
                else:
                        var abs_path: String = ProjectSettings.globalize_path(tex_path)
                        if FileAccess.file_exists(abs_path):
                                var img := Image.new()
                                if img.load(abs_path) == OK:
                                        tex = ImageTexture.create_from_image(img)
                                        if tex != null:
                                                _maze_treasure_cache[tex_path] = tex
                if tex != null:
                        # FIX (tesori "ridurre di poco"): 64*1.3=83.2px era più
                        # grande degli stessi nemici. 64*1.15=73.6px (-12%):
                        # il tesoro resta ben visibile ma la gerarchia diventa
                        # player (83) > miniboss (82) > nemici (78) > tesori
                        # (73.6). Contenuto reale PNG ~68px, dentro la cella.
                        # TASK 81c: le GEMME (zaffiro blu + rubino rosso) si
                        # rimpiccioliscono del 30% (73.6 -> 51.5px): da "più
                        # grandi dei nemici" a oggetto minore nel corridoio.
                        var draw_size: float = size * 1.15
                        if tres_type == C.TreasureType.GEM \
                                        or tres_type == C.TreasureType.RUBY:
                                draw_size *= C.TREASURE_GEM_SHRINK
                        draw_texture_rect(tex,
                                Rect2(px + (size - draw_size) / 2.0, py + (size - draw_size) / 2.0,
                                        draw_size, draw_size), false)
                        return
        # Fallback: texture procedurali EnvironmentArt
        if EnvironmentArt:
                var tex: Texture2D = EnvironmentArt.get_treasure_texture(tres_type)
                if tex:
                        var draw_size: float = size * 1.15  # FIX: era 0.8, poi 1.3, ora 1.15 (73.6px)
                        # TASK 81c: gemme -30% (stessa regola del PNG).
                        if tres_type == C.TreasureType.GEM \
                                        or tres_type == C.TreasureType.RUBY:
                                draw_size *= C.TREASURE_GEM_SHRINK
                        draw_texture_rect(tex,
                                Rect2(px + (size - draw_size) / 2.0, py + (size - draw_size) / 2.0,
                                        draw_size, draw_size), false)
                        return
        # Fallback: semplice gem colorato
        var ped_rect := Rect2(px + size * 0.2, py + size * 0.6, size * 0.6, size * 0.2)
        draw_rect(ped_rect, Color(0.45, 0.40, 0.35), true)
        var gem_color: Color = C.PALETTE[C.PAL_GOLD]
        match tres_type:
                C.TreasureType.CROWN: gem_color = C.PALETTE[C.PAL_GOLD]
                C.TreasureType.GOLD: gem_color = Color(1.0, 0.84, 0.0)
                C.TreasureType.CHEST: gem_color = Color(0.55, 0.30, 0.15)
                C.TreasureType.GEM: gem_color = C.PALETTE[C.PAL_CYAN]
                C.TreasureType.RUBY: gem_color = C.PALETTE[C.PAL_RED]
        var cx: float = px + size * 0.5
        var cy: float = py + size * 0.45
        var gs: float = size * 0.18
        # TASK 81c: gemme -30% anche nel fallback poligonale.
        if tres_type == C.TreasureType.GEM \
                        or tres_type == C.TreasureType.RUBY:
                gs *= C.TREASURE_GEM_SHRINK
        var points := PackedVector2Array([
                Vector2(cx, cy - gs), Vector2(cx + gs, cy),
                Vector2(cx, cy + gs), Vector2(cx - gs, cy),
        ])
        draw_colored_polygon(points, gem_color)
        draw_line(Vector2(cx, cy - gs), Vector2(cx + gs, cy), Color(1.0, 1.0, 1.0, 0.6), 1.5)


func _render_weapon_cell(px: float, py: float, size: float, weapon: Dictionary) -> void:
        # Usa le texture procedurali dettagliate da EnvironmentArt
        # (pistola/fucile/razzo/laser) invece di semplici quadrati.
        # TASK 50 (armi troppo grandi): le texture sono ora NORMALIZZATE al
        # 75% del canvas da EnvironmentArt._normalize_weapon_content, quindi
        # basta un draw uniforme a dimensione cella: ogni arma occupa ~48px
        # visivi (0.75 tile), come martello/shotgun dello screenshot utente.
        # Il vecchio multiplier 1.6x della pistola e' stato RIMOSSO: era il
        # motivo per cui pistola e razzo sembravano pezzi esterni giganti.
        var wpn_type: int = weapon.get("type", C.WeaponType.PISTOL)
        if EnvironmentArt:
                var tex: Texture2D = EnvironmentArt.get_weapon_pickup_texture(wpn_type)
                if tex:
                        var draw_size: float = size * 1.0
                        draw_texture_rect(tex,
                                Rect2(px + (size - draw_size) / 2.0, py + (size - draw_size) / 2.0,
                                        draw_size, draw_size), false)
                        return
        # Fallback: quadrato colorato
        var col: Color = C.get_weapon_color(wpn_type)
        var wrect := Rect2(px + size * 0.25, py + size * 0.25, size * 0.5, size * 0.5)
        draw_rect(wrect, col, true)
        draw_rect(wrect, Color(0.10, 0.10, 0.10), false, 1.5)


# ============================================================================
# GALLERIE "PAC-MAN" — deformazione a SEMILUNA del muro di bordo
# ============================================================================
# Le 4 aperture nel muro di bordo (alto/basso al centro sulla colonna 15,
# sinistra/destra al centro sulla riga 7) sono rese con UNA SEMPLICE
# DEFORMAZIONE A SEMILUNA del muro (richiesta utente: "elimina quella
# grafica dei fori, applica solo una deformazione a semiluna"): niente
# conci, glow, chiave di volta, crepe o soglie — solo i due angoli del
# muro che fiancheggiano ogni imbocco vengono arrotondati con un quarto
# di cerchio (raggio meta' cella), cosi' la bocca della galleria ha il
# profilo a semiluna. Il foro e' largo ESATTAMENTE 1 cella (64px) su
# TUTTI e 4 i lati (prima alto/basso erano larghi 2 celle = 128px:
# "i fori sopra e sotto piu' grandi di quelli laterali").
#
# La zona arrotondata e' riempita col colore del gradiente del pavimento
# (stessa formula di _render_floor_gradient, campionata dentro lo scalone)
# e l'arco e' profilato con la stessa matita scura del bordo delle celle
# muro: la galleria sembra un pezzo di muro DEFORMATO, non un decal
# incollato sopra.


# Colore del gradiente del pavimento nel punto (x, y): replica la formula
# a quad 8x8 di _render_floor_gradient e ritorna il colore del quad che
# contiene il punto, cosi' lo scalone si fonde col pavimento gia' disegnato
# intorno all'imbocco.
func _floor_gradient_color_at(x: float, y: float) -> Color:
        var center_c: float = C.MAZE_COLS / 2.0
        var center_r: float = C.MAZE_ROWS / 2.0
        var step_x: float = C.MAZE_COLS * C.TILE_SIZE / 8.0
        var step_y: float = C.MAZE_ROWS * C.TILE_SIZE / 8.0
        var sx: float = clampf(floor(x / step_x), 0.0, 7.0)
        var sy: float = clampf(floor((y - C.UI_HEIGHT) / step_y), 0.0, 7.0)
        var cell_cx: float = (sx + 0.5) * step_x / C.TILE_SIZE
        var cell_cy: float = (sy + 0.5) * step_y / C.TILE_SIZE
        var dx: float = (cell_cx - center_c) / center_c
        var dy: float = (cell_cy - center_r) / center_r
        var dist: float = clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
        var brightness: float = 24.0 - dist * 18.0
        return Color(
                clampf(bg_color.r + brightness / 255.0, 0.0, 1.0),
                clampf(bg_color.g + brightness * 0.7 / 255.0, 0.0, 1.0),
                clampf(bg_color.b + brightness * 0.4 / 255.0, 0.0, 1.0),
        )


# Disegna un quarto di disco (scalone a semiluna) con centro `center`,
# raggio `radius`, nel quadrante (sx, sy): es. sx=-1 e sy=-1 = quarto di
# disco in alto a sinistra del centro (dentro il muro che fiancheggia
# l'imbocco). Il riempimento usa il colore pavimento campionato al
# baricentro dello scalone; l'arco e' profilato col bordo scuro usato
# anche per il perimetro delle celle muro.
func _draw_halfmoon_scallop(center: Vector2, radius: float, sx: float, sy: float) -> void:
        var fill: Color = _floor_gradient_color_at(
                center.x + sx * radius * 0.5, center.y + sy * radius * 0.5)
        var pts := PackedVector2Array()
        pts.append(center)
        const SEG: int = 10
        for i in range(SEG + 1):
                var t: float = float(i) / float(SEG)
                var a: float = t * PI * 0.5
                pts.append(center + Vector2(
                        sx * cos(a) * radius, sy * sin(a) * radius))
        draw_colored_polygon(pts, fill)
        # Bordo dell'arco: stessa matita scura del perimetro delle celle muro
        # (vedi _render_wall_cell), cosi' il "taglio" della semiluna si
        # presenta come il bordo del muro stesso.
        var arc := pts.slice(1, pts.size())
        draw_polyline(arc, Color(0.04, 0.04, 0.04), 1.5, true)


# Disegna la deformazione a semiluna sulle 4 bocche di galleria (chiamata
# da _draw() DOPO celle e decorazioni: gli scaloni coprono gli angoli
# delle celle muro che fiancheggiano ogni imbocco). Geometria: ogni
# imbocco e' largo 1 cella; i due angoli del muro sul lato che guarda il
# labirinto vengono smussati con un quarto di cerchio di raggio meta'
# cella -> la bocca si allarga dolcemente a semiluna verso il interno.
func _draw_tunnel_halfmoons() -> void:
        var r: float = C.TILE_SIZE * 0.5        # semiluna piena (32px)
        var half: float = C.TILE_SIZE * 0.5    # semi-larghezza imbocco
        var tb_col: float = float(C.TUNNEL_COLS_TOP_BOTTOM[0])
        var cx: float = (tb_col + 0.5) * C.TILE_SIZE  # centro imbocco alto/basso
        # --- Tunnel ALTO (colonna 15, riga 0): angoli INFERIORI dei muri
        #     che fiancheggiano l'imbocco, lato che guarda il labirinto.
        var top_y: float = C.UI_HEIGHT + C.TILE_SIZE
        _draw_halfmoon_scallop(Vector2(cx - half, top_y), r, -1.0, -1.0)
        _draw_halfmoon_scallop(Vector2(cx + half, top_y), r, 1.0, -1.0)
        # --- Tunnel BASSO (colonna 15, riga 14): angoli SUPERIORI.
        var bot_y: float = C.UI_HEIGHT + (C.MAZE_ROWS - 1) * C.TILE_SIZE
        _draw_halfmoon_scallop(Vector2(cx - half, bot_y), r, -1.0, 1.0)
        _draw_halfmoon_scallop(Vector2(cx + half, bot_y), r, 1.0, 1.0)
        # --- Tunnel SINISTRA (riga 7, colonna 0): angoli DESTRI dei muri
        #     sopra e sotto l'imbocco (la faccia interna del muro e' x=64).
        var side_cy: float = (float(C.TUNNEL_ROW_SIDES) + 0.5) * C.TILE_SIZE + C.UI_HEIGHT
        _draw_halfmoon_scallop(Vector2(C.TILE_SIZE, side_cy - half), r, -1.0, -1.0)
        _draw_halfmoon_scallop(Vector2(C.TILE_SIZE, side_cy + half), r, -1.0, 1.0)
        # --- Tunnel DESTRA (riga 7, colonna 29): angoli SINISTRI
        #     (faccia interna del muro e' x=1856).
        var right_x: float = (C.MAZE_COLS - 1) * C.TILE_SIZE
        _draw_halfmoon_scallop(Vector2(right_x, side_cy - half), r, 1.0, -1.0)
        _draw_halfmoon_scallop(Vector2(right_x, side_cy + half), r, 1.0, 1.0)

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
## Floor color for the current palette.
var bg_color: Color = Color(0.11, 0.09, 0.07, 1.0)

# 8 color palettes that cycle per level (1:1 from Maze.cpp).
#  Index 0 = grey cavern, 1 = blue dungeon, 2 = purple crypt, 3 = red rock,
#  4 = bone ossuary, 5 = green swamp, 6 = red hell, 7 = teal abyss.
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

# Per-cell placement constants (from Maze.cpp).
const _NUM_EXTRA_OPENINGS: int = 15
const _TREASURES_PER_LEVEL: int = 8
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


func _draw() -> void:
        # Always redraw - the C++ Maze::render also draws every frame because
        # torches animate. For static mazes you can gate this on needs_redraw.
        _render_floor_gradient()
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        _render_cell(c, r)
        # Decora alcune celle WALL con teschi, ragnatele, crepe
        # (vantaggio Godot: texture procedurali ad alta risoluzione)
        _render_wall_decorations()


# Variabili per le luci delle torce (create una volta in generate)
var _torch_lights: Array = []
# Posizioni delle torce per disegnarle nel _render_wall_decorations
var _torch_positions: Array = []


# Renderizza decorazioni procedurali sulle pareti del dungeon.
# Usa un seed deterministico basato su (c,r,level) per posizionare in modo
# consistente teschi/ragnatele/creppe su certe celle WALL.
func _render_wall_decorations() -> void:
        if not EnvironmentArt:
                return
        var skull_tex: Texture2D = EnvironmentArt.get_skull_texture()
        var cobweb_tex: Texture2D = EnvironmentArt.get_cobweb_texture()
        var torch_tex: Texture2D = EnvironmentArt.get_torch_texture()
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if not is_wall(c, r):
                                continue
                        # Hash deterministico per scegliere decorazione
                        var h: int = (c * 73856093) ^ (r * 19349663) ^ (level * 83492791)
                        var hash_val: int = abs(h) % 100
                        var px: float = c * C.TILE_SIZE
                        var py: float = r * C.TILE_SIZE + C.UI_HEIGHT
                        var size: float = C.TILE_SIZE
                        # ~8% teschi (solo su celle interne)
                        if hash_val < 8 and c > 2 and c < C.MAZE_COLS - 2 and r > 2 and r < C.MAZE_ROWS - 2:
                                if skull_tex:
                                        draw_texture_rect(skull_tex,
                                                Rect2(px + size * 0.15, py + size * 0.1,
                                                      size * 0.7, size * 0.7), false)
                        # ~6% ragnatele (angoli)
                        elif hash_val < 14 and (c <= 2 or c >= C.MAZE_COLS - 3 or r <= 2 or r >= C.MAZE_ROWS - 3):
                                if cobweb_tex:
                                        draw_texture_rect(cobweb_tex,
                                                Rect2(px, py, size * 0.8, size * 0.8), false)
                        # ~5% torce (sprite solo; le luci sono create in generate)
                        elif hash_val < 19 and c > 1 and c < C.MAZE_COLS - 2:
                                if torch_tex:
                                        draw_texture_rect(torch_tex,
                                                Rect2(px + size * 0.2, py - size * 0.3,
                                                      size * 0.6, size * 0.9), false)


# Crea le PointLight2D per le torce una volta sola (chiamato da generate).
# Le luci sono figli del Maze node e seguono le posizioni delle torce.
func _spawn_torch_lights() -> void:
        # Rimuovi le luci precedenti
        for light in _torch_lights:
                if is_instance_valid(light):
                        light.queue_free()
        _torch_lights.clear()
        _torch_positions.clear()
        if not EffectsManager:
                return
        for c in range(C.MAZE_COLS):
                for r in range(C.MAZE_ROWS):
                        if not is_wall(c, r):
                                continue
                        var h: int = (c * 73856093) ^ (r * 19349663) ^ (level * 83492791)
                        var hash_val: int = abs(h) % 100
                        if hash_val >= 14 and hash_val < 19 and c > 1 and c < C.MAZE_COLS - 2:
                                var px: float = c * C.TILE_SIZE + C.TILE_SIZE * 0.5
                                var py: float = r * C.TILE_SIZE + C.UI_HEIGHT - C.TILE_SIZE * 0.1
                                var light: PointLight2D = EffectsManager.create_light(
                                        Vector2(px, py),
                                        Color(1.0, 0.7, 0.3, 1.0),
                                        1.2,  # energy
                                        80.0  # radius
                                )
                                add_child(light)
                                _torch_lights.append(light)
                                _torch_positions.append(Vector2(px, py))


# ============================================================================
# GENERATION  (port of Maze::generate)
# ============================================================================
## Regenerate the maze for `lvl`. Mirrors Maze::generate(level) line-by-line.
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
                        _set_cell_treasure(cc, rr, randi() % 5)  # TRES_CROWN..TRES_CUP
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
                        _set_cell_weapon(cell.x, cell.y, C.make_random_weapon())
                        placed_items.append(cell)
                        weapons_placed += 1

                # 7) Pick the palette for this level.
        var pal_idx: int = C.get_palette_index(level)
        var pal: Dictionary = _PALETTES[pal_idx]
        wall_color = pal["wall"]
        bg_color = pal["bg"]

        # Crea le PointLight2D per le torce sulle pareti (vantaggio Godot).
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
func is_wall(col: int, row: int) -> bool:
        if col < 0 or col >= C.MAZE_COLS or row < 0 or row >= C.MAZE_ROWS:
                return true
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


## Renders a single cell. WALL -> 5-band rocky gradient; TREASURE ->
## pedestal + simple icon; WEAPON -> colored square (full Weapon rendering
## belongs to a Weapon.gd scene, not the maze).
func _render_cell(c: int, r: int) -> void:
        var cell_type: int = _get_cell_type(c, r)
        var px: float = c * C.TILE_SIZE
        var py: float = r * C.TILE_SIZE + C.UI_HEIGHT
        var size: float = C.TILE_SIZE

        match cell_type:
                C.CellType.WALL:
                        _render_wall_cell(px, py, size)
                C.CellType.TREASURE:
                        _render_treasure_cell(px, py, size, _get_cell_treasure(c, r))
                C.CellType.WEAPON:
                        _render_weapon_cell(px, py, size, _get_cell_weapon(c, r))
                C.CellType.EMPTY, _:
                        pass  # Floor is already drawn by the gradient.


## Draws a WALL cell as a 5-band vertical gradient, mirroring the C++
## "rocky dungeon" effect: bright top (torch-lit) -> dark bottom (shadow).
func _render_wall_cell(px: float, py: float, size: float) -> void:
        # Band 5 - deepest shadow at the bottom, covers the full cell.
        var col_bottom := Color(
                maxf(wall_color.r - 55.0 / 255.0, 0.0),
                maxf(wall_color.g - 50.0 / 255.0, 0.0),
                maxf(wall_color.b - 45.0 / 255.0, 0.0),
        )
        draw_rect(Rect2(px, py, size, size), col_bottom, true)
        # Band 4 - mid shadow on the lower 75%.
        var col_low := Color(
                maxf(wall_color.r - 25.0 / 255.0, 0.0),
                maxf(wall_color.g - 22.0 / 255.0, 0.0),
                maxf(wall_color.b - 20.0 / 255.0, 0.0),
        )
        draw_rect(Rect2(px, py + size * 0.25, size, size * 0.75), col_low, true)
        # Band 3 - base tone on the upper 55%.
        var col_mid := Color(
                maxf(wall_color.r - 5.0 / 255.0, 0.0),
                maxf(wall_color.g - 5.0 / 255.0, 0.0),
                maxf(wall_color.b - 5.0 / 255.0, 0.0),
        )
        draw_rect(Rect2(px, py, size, size * 0.55), col_mid, true)
        # Band 2 - mid-light on the upper 30%.
        var col_light := Color(
                minf(wall_color.r + 22.0 / 255.0, 1.0),
                minf(wall_color.g + 22.0 / 255.0, 1.0),
                minf(wall_color.b + 22.0 / 255.0, 1.0),
        )
        draw_rect(Rect2(px, py, size, size * 0.30), col_light, true)
        # Band 1 - brightest highlight on the top band.
        var col_top := Color(
                minf(wall_color.r + 50.0 / 255.0, 1.0),
                minf(wall_color.g + 50.0 / 255.0, 1.0),
                minf(wall_color.b + 50.0 / 255.0, 1.0),
        )
        draw_rect(Rect2(px, py, size, size * 0.12), col_top, true)
        # Dark outline so adjacent walls read as one mass.
        draw_rect(Rect2(px, py, size, size), Color(0.04, 0.04, 0.04), false, 1.0)


## Draws a treasure cell: small stone pedestal + colored gem marker that
## varies by TreasureType. The C++ version draws full sprite art with
## primitives; we render a simpler version that's still distinct per type.
func _render_treasure_cell(px: float, py: float, size: float, tres_type: int) -> void:
        # Pedestal
        var ped_rect := Rect2(px + size * 0.2, py + size * 0.6, size * 0.6, size * 0.2)
        draw_rect(ped_rect, Color(0.45, 0.40, 0.35), true)
        draw_rect(ped_rect, Color(0.20, 0.18, 0.15), false, 1.0)
        # Gem / item color depends on treasure type.
        var gem_color: Color = C.PALETTE[C.PAL_GOLD]
        match tres_type:
                C.TreasureType.CROWN:
                        gem_color = C.PALETTE[C.PAL_GOLD]
                C.TreasureType.GOLD:
                        gem_color = Color(1.0, 0.84, 0.0)
                C.TreasureType.CHEST:
                        gem_color = Color(0.55, 0.30, 0.15)
                C.TreasureType.GEM:
                        gem_color = C.PALETTE[C.PAL_CYAN]
                C.TreasureType.CUP:
                        gem_color = C.PALETTE[C.PAL_GOLD]
                # Gem body (small diamond)

                # Highlight on the upper facet
        var cx: float = px + size * 0.5
        var cy: float = py + size * 0.45
        var gs: float = size * 0.18
        var points := PackedVector2Array(
                [
                        Vector2(cx, cy - gs),
                        Vector2(cx + gs, cy),
                        Vector2(cx, cy + gs),
                        Vector2(cx - gs, cy),
                ]
        )
        draw_colored_polygon(points, gem_color)
        # Highlight on the upper facet
        draw_line(Vector2(cx, cy - gs), Vector2(cx + gs, cy), Color(1.0, 1.0, 1.0, 0.6), 1.5)


## Draws a weapon cell: a colored square indicating the weapon type. The
## full weapon sprite (with shadow, shape, outline) belongs to a Weapon.gd
## scene; the maze just shows a placeholder marker.
func _render_weapon_cell(px: float, py: float, size: float, weapon: Dictionary) -> void:
        var wpn_type: int = weapon.get("type", C.WeaponType.PISTOL)
        var col: Color = C.get_weapon_color(wpn_type)
        var wrect := Rect2(px + size * 0.25, py + size * 0.25, size * 0.5, size * 0.5)
        draw_rect(wrect, col, true)
        draw_rect(wrect, Color(0.10, 0.10, 0.10), false, 1.5)

# ===========================================================================
# EnemySpawner.gd - Spawns enemy waves for Arcade Maze Fantasy (Godot port).
#
# Port of the spawning logic in src/Game.cpp:
#   * spawnEnemies()           (line 373-400) - initial wave per maze level
#   * spawnEnemyFromPortal()    (line 407-447) - respawn from magic portal
#   * Magic-portal activation   (line 1949-2101) - 50%-killed trigger with
#     3 enemies + 1 mini-boss.
#
# Public API:
#   spawn_enemies(maze)               - place 5 random enemies at level start
#   trigger_portal(maze, player_pos)  - open magic portal at 50% kills
#   update_portal(maze, dt_ms)        - tick the portal's open/spawn/close
#                                       state machine; respawns enemies
#                                       one-at-a-time every 4 s
#
# The spawner owns:
#   * `enemies`       : Array[Enemy] - the live enemy pool (Game reads this)
#   * `magic_portal`  : portal state (position, phase, spawn queue)
#   * `initial_count`  : snapshot of enemies.size() at level start, used
#                        to compute the 50% threshold
#   * `portal_used`    : one-shot latch - portal fires at most once / level
# ===========================================================================
class_name EnemySpawner
extends Node

# --- Grid constants (mirror Utils.h) ----------------------------------------
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19
const UI_HEIGHT: int = 80

# --- Cell type constants (mirror Maze.h CellType) ---------------------------
const CELL_EMPTY: int = 0
const CELL_WALL: int = 1
const CELL_TREASURE: int = 2
const CELL_WEAPON: int = 3

# --- Spawning tuning --------------------------------------------------------
const INITIAL_WAVE_SIZE: int = 5
const PORTAL_ENEMIES_TO_SPAWN: int = 3
# Portal phase timers (ms simulated) - mirror Game.cpp line 1979-2140.
const PORTAL_OPEN_MS: int = 1000     # phase 0: portal opening
const PORTAL_CLOSE_MS: int = 800     # phase 2: portal closing
const PORTAL_FIRST_SPAWN_MS: int = 500   # delay before first respawn
const PORTAL_SPAWN_INTERVAL_MS: int = 4000  # 4 s between respawns
# Cell-search radius when placing a respawned enemy near the portal.
const PORTAL_PLACE_MAX_RADIUS: int = 5

# --- Public state -----------------------------------------------------------

# Live enemy pool. Game iterates over this each frame to call update_enemy.
var enemies: Array = []  # Array[Enemy]

# Magic portal state machine.
# Phases: 0=opening, 1=spawning, 2=closing, 3=inactive.
var magic_portal: Dictionary = {
        "pos": Vector2.ZERO,
        "active": false,
        "phase": 3,
        "phase_timer": 0,
        "rotation": 0.0,
        "glow_pulse": 0.0,
        "enemies_to_spawn": 0,
        "spawn_timer": 0,
        "dead_indices": [],   # indices into `enemies` array for respawn
}

# Initial count for 50% trigger (snapshot taken in spawn_enemies()).
var initial_count: int = 0
# One-shot latch: portal triggers at most once per maze level.
var portal_used: bool = false

# Enemy scene - override from inspector if you have a custom .tscn.
# Default: use the Enemy.gd script directly via `Enemy.new()`.
@export var enemy_scene: PackedScene = null


# ===========================================================================
# spawn_enemies(maze): generate 5 random enemies at level start.
#
# Logic (mirror Game::spawnEnemies() src/Game.cpp line 373-400):
#   * Type chosen uniformly from all 28 EnemyType values.
#   * Position random until a non-wall cell is found that's NOT in the
#     player's safe-startup zone (col < 5 AND row < 5) - gives the player
#     a few seconds of breathing room at the start of a level.
#   * Replaces any previous wave (clears the pool).
# ===========================================================================
func spawn_enemies(maze: Object) -> void:
        enemies.clear()
        for i in range(INITIAL_WAVE_SIZE):
                var t: int = randi() % Enemy.ENEMY_TYPE_COUNT
                var c: int
                var r: int
                # Find a valid spawn cell: not a wall, not in the 5x5 starting zone.
                # (Game.cpp condition: while (isWall || (c<5 && r<5)))
                var attempts: int = 0
                while true:
                        c = 1 + randi() % (MAZE_COLS - 2)
                        r = 1 + randi() % (MAZE_ROWS - 2)
                        attempts += 1
                        if attempts > 200:
                                break  # safety: maze degenerate, give up searching
                        if not maze.is_wall(c, r) and not (c < 5 and r < 5):
                                break
                _spawn_enemy_instance(t, c, r)
        # Snapshot for the 50% portal trigger.
        initial_count = enemies.size()
        portal_used = false
        # Reset portal state to inactive.
        magic_portal.active = false
        magic_portal.phase = 3
        magic_portal.phase_timer = 0
        magic_portal.enemies_to_spawn = 0
        magic_portal.dead_indices.clear()


# ===========================================================================
# _spawn_enemy_instance(type, col, row): create one Enemy, init it, and
# add to the pool. Centralised so spawn_enemies() and update_portal() can
# share the same code path.
# ===========================================================================
func _spawn_enemy_instance(t: int, col: int, row: int) -> Enemy:
        var e: Enemy
        if enemy_scene != null:
                e = enemy_scene.instantiate() as Enemy
        else:
                e = Enemy.new()
        e.init(t, col, row)
        # If the spawner is in the tree, also add the enemy as a sibling so it
        # gets rendered (caller may instead opt to add to a YSort node).
        if get_parent():
                get_parent().add_child(e)
        enemies.append(e)
        return e


# ===========================================================================
# trigger_portal_if_needed(maze, player_pos): check the 50%-killed
# threshold and open the magic portal when crossed. Spawns the mini-boss
# next to the portal at the same moment (see Game.cpp line 1996-2093).
#
# Returns true if the portal was opened THIS call.
# ===========================================================================
func trigger_portal_if_needed(maze: Object, player_pos: Vector2,
                                                          mini_boss_spawner: Callable = Callable()) -> bool:
        if portal_used or initial_count <= 0:
                return false

        # Count alive enemies (health > 0).
        var alive_count: int = 0
        for e in enemies:
                if e is Enemy and not e.is_dead():
                        alive_count += 1

        if alive_count > initial_count / 2 or alive_count <= 0:
                return false

        # --- 50% threshold crossed: open the portal at the maze centre ---
        # Search for the empty cell closest to (MAZE_COLS/2, MAZE_ROWS/2).
        var target_c: int = MAZE_COLS / 2
        var target_r: int = MAZE_ROWS / 2
        var best_c: int = -1
        var best_r: int = -1
        var best_dist: int = 999
        for c in range(1, MAZE_COLS - 1):
                for r in range(1, MAZE_ROWS - 1):
                        if maze.get_cell_type(c, r) == CELL_EMPTY:
                                var d: int = abs(c - target_c) + abs(r - target_r)
                                if d < best_dist:
                                        best_dist = d
                                        best_c = c
                                        best_r = r

        if best_c < 0:
                return false  # no empty cell found (degenerate maze) - abort

        # Position the portal at the centre of that cell.
        magic_portal.pos = Vector2(
                best_c * TILE_SIZE + TILE_SIZE / 2.0,
                best_r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0
        )
        magic_portal.active = true
        magic_portal.phase = 0
        magic_portal.phase_timer = PORTAL_OPEN_MS
        magic_portal.rotation = 0.0
        magic_portal.glow_pulse = 0.0
        magic_portal.enemies_to_spawn = PORTAL_ENEMIES_TO_SPAWN
        if magic_portal.enemies_to_spawn > initial_count:
                magic_portal.enemies_to_spawn = initial_count
        magic_portal.spawn_timer = 0
        magic_portal.dead_indices.clear()

        # Collect indices of fully-dead enemies (death anim done) so we can
        # respawn the same types near the portal.
        for i in range(enemies.size()):
                var e = enemies[i]
                if e is Enemy and e.is_dead() and e.is_death_anim_done():
                        magic_portal.dead_indices.append(i)

        portal_used = true

        # --- Spawn the mini-boss next to the portal ---
        # Game.cpp line 2013-2093: search a free cell at radius 1..4 from the
        # portal; if none, fall back to the cell FARTHEST from the player.
        if mini_boss_spawner.is_valid():
                var mb_pos := _find_mini_boss_cell(maze, magic_portal.pos, player_pos)
                if mb_pos.x >= 0:
                        mini_boss_spawner.call(mb_pos.x, mb_pos.y)

        return true


# _find_mini_boss_cell(maze, portal_pos, player_pos): locate an empty cell
# near the portal (radius 1..4) for the mini-boss to appear. Falls back to
# the cell farthest from the player (>=6 manhattan distance) if none nearby.
# Returns Vector2i(col, row) or Vector2i(-1, -1) if nothing suitable exists.
# Mirrors Game.cpp line 2014-2057.
func _find_mini_boss_cell(maze: Object, portal_pos: Vector2,
                                                  player_pos: Vector2) -> Vector2i:
        var portal_c := int(portal_pos.x / TILE_SIZE)
        var portal_r := int((portal_pos.y - UI_HEIGHT) / TILE_SIZE)
        # Try cells in expanding rings around the portal.
        for radius in range(1, 5):
                for dc in range(-radius, radius + 1):
                        for dr in range(-radius, radius + 1):
                                var nc: int = portal_c + dc
                                var nr: int = portal_r + dr
                                if nc <= 0 or nc >= MAZE_COLS - 1:
                                        continue
                                if nr <= 0 or nr >= MAZE_ROWS - 1:
                                        continue
                                if maze.is_wall(nc, nr):
                                        continue
                                if maze.get_cell_type(nc, nr) != CELL_EMPTY:
                                        continue
                                if nc == portal_c and nr == portal_r:
                                        continue  # don't sit on top of the portal
                                return Vector2i(nc, nr)

        # Fallback: farthest empty cell from the player (>=6 manhattan dist).
        var pc := int(player_pos.x / TILE_SIZE)
        var pr := int((player_pos.y - UI_HEIGHT) / TILE_SIZE)
        var fallback_best_dist: int = -1
        var fb_c: int = -1
        var fb_r: int = -1
        for c in range(1, MAZE_COLS - 1):
                for r in range(1, MAZE_ROWS - 1):
                        if maze.get_cell_type(c, r) == CELL_EMPTY and not maze.is_wall(c, r):
                                var dist: int = abs(c - pc) + abs(r - pr)
                                if dist >= 6 and dist > fallback_best_dist:
                                        fallback_best_dist = dist
                                        fb_c = c
                                        fb_r = r
        return Vector2i(fb_c, fb_r)


# ===========================================================================
# update_portal(maze, dt_ms): tick the portal state machine.
# dt_ms is simulated ms (call with 16 each _physics_process frame).
# Returns true if the portal is still active (Game should keep ticking).
# ===========================================================================
func update_portal(maze: Object, dt_ms: int) -> bool:
        if not magic_portal.active:
                return false

        # Animate portal rotation + glow (visual cue; rendered by Game node).
        magic_portal.rotation += 0.03
        magic_portal.glow_pulse += 0.016

        magic_portal.phase_timer = max(0, magic_portal.phase_timer - dt_ms)

        if magic_portal.phase_timer == 0:
                if magic_portal.phase == 0:
                        # Opening complete -> start spawning.
                        magic_portal.phase = 1
                        magic_portal.spawn_timer = PORTAL_FIRST_SPAWN_MS
                        _spawn_enemy_from_portal(maze)
                elif magic_portal.phase == 2:
                        # Closing complete -> deactivate.
                        magic_portal.phase = 3
                        magic_portal.active = false
                        return false

        # Phase 1: spawn enemies one-by-one on a 4-second interval.
        if magic_portal.phase == 1:
                magic_portal.spawn_timer = max(0, magic_portal.spawn_timer - dt_ms)
                if magic_portal.spawn_timer == 0 and magic_portal.enemies_to_spawn > 0:
                        _spawn_enemy_from_portal(maze)
                        magic_portal.spawn_timer = PORTAL_SPAWN_INTERVAL_MS
                # All enemies spawned -> close portal.
                if magic_portal.enemies_to_spawn == 0:
                        magic_portal.phase = 2
                        magic_portal.phase_timer = PORTAL_CLOSE_MS

        return magic_portal.active


# ===========================================================================
# _spawn_enemy_from_portal(maze): respawn ONE dead enemy next to the
# portal. Picks the first dead enemy index, finds an empty cell in an
# expanding ring around the portal, and recreates that enemy there.
# Mirrors Game::spawnEnemyFromPortal() src/Game.cpp line 407-447.
# ===========================================================================
func _spawn_enemy_from_portal(maze: Object) -> void:
        if magic_portal.enemies_to_spawn <= 0 or magic_portal.dead_indices.is_empty():
                magic_portal.enemies_to_spawn = 0
                return

        var idx: int = magic_portal.dead_indices.pop_back()
        if idx < 0 or idx >= enemies.size():
                magic_portal.enemies_to_spawn -= 1
                return

        var e: Enemy = enemies[idx]
        if e == null or not (e is Enemy):
                magic_portal.enemies_to_spawn -= 1
                return

        var et: int = e.get_type()
        var pc := int(magic_portal.pos.x / TILE_SIZE)
        var pr := int((magic_portal.pos.y - UI_HEIGHT) / TILE_SIZE)

        # Expanding-ring search for an empty cell near the portal.
        var placed: bool = false
        for radius in range(1, PORTAL_PLACE_MAX_RADIUS + 1):
                if placed:
                        break
                for dc in range(-radius, radius + 1):
                        if placed:
                                break
                        for dr in range(-radius, radius + 1):
                                var nc: int = pc + dc
                                var nr: int = pr + dr
                                if nc <= 0 or nc >= MAZE_COLS - 1:
                                        continue
                                if nr <= 0 or nr >= MAZE_ROWS - 1:
                                        continue
                                if maze.is_wall(nc, nr):
                                        continue
                                if maze.get_cell_type(nc, nr) != CELL_EMPTY:
                                        continue
                                # Re-init the existing Enemy instance at the new cell.
                                # This reuses the node (no add/remove churn) and preserves
                                # its sprite etc. - mirrors `enemies[idx] = Enemy(et, nc, nr)`.
                                e.init(et, nc, nr)
                                placed = true
                                break

        magic_portal.enemies_to_spawn -= 1


# ===========================================================================
# Accessors / convenience
# ===========================================================================

# alive_count(): how many enemies are still alive (HP > 0). Useful for the
# Game node to check end-of-wave conditions and the portal trigger.
func alive_count() -> int:
        var n: int = 0
        for e in enemies:
                if e is Enemy and not e.is_dead():
                        n += 1
        return n


# clear(): empty the pool AND free any enemy nodes that are children.
# Called by Game at level transition.
func clear() -> void:
        for e in enemies:
                if e is Node and is_instance_valid(e):
                        e.queue_free()
        enemies.clear()
        initial_count = 0
        portal_used = false
        magic_portal.active = false
        magic_portal.phase = 3
        magic_portal.enemies_to_spawn = 0
        magic_portal.dead_indices.clear()


# remove_dead(done_anim=true): drop fully-dead enemies from the pool.
# Game calls this after rendering to keep the array compact.
func remove_dead() -> void:
        var alive: Array = []
        for e in enemies:
                if e is Enemy and not e.is_death_anim_done():
                        alive.append(e)
                else:
                        if e is Node and is_instance_valid(e):
                                e.queue_free()
        enemies = alive

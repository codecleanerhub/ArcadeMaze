# ===========================================================================
# Enemy.gd - Maze enemy for Arcade Maze Fantasy (Godot port).
#
# Port of src/Enemy.h and src/Enemy.cpp (SFML/C++ -> GDScript).
#
# 28 enemy types share this single class; behaviour differs by `type`:
#   * All enemies use BFS to chase the player (path re-computed every
#     ~200 ms, or immediately when idle / stuck / flee-mode flips).
#   * When the player is invincible (chalice), fleeGreedy() runs instead:
#     it picks the adjacent cell that MAXIMISES distance from the player.
#   * Shooting types (SKELETON, CULTIST, DEMON, WRAITH, ROBOT, WITCH,
#     MAD_WIZARD) fire at the player within 500 px, every 1-2.5 s.
#   * Anti-stuck tracker: if the enemy barely moves for > 600 ms, it picks
#     a random open direction to break out of local minima.
#
# Movement is grid-aligned (snap-to-cell-centre before turning), exactly
# like the Player. AnimTime is a continuously-growing timer NEVER reset by
# the BFS update so walk/idle animations keep a steady cadence.
# ===========================================================================
class_name Enemy
extends Node2D

# --- Grid constants (mirror Utils.h) ---------------------------------------
const WINDOW_WIDTH: int = 1024
const WINDOW_HEIGHT: int = 1024
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19
const UI_HEIGHT: int = 80

# --- EnemyType (mirror Enemy.h enum, 28 types) ------------------------------
# Order is significant: Game::spawnEnemies picks from this set randomly,
# so re-ordering would shift the spawn distribution.
enum EnemyType {
	# --- 15 original types ---
	ZOMBIE, SKELETON, GHOST, BAT,
	SPIDER, SLIME, DEMON, ROBOT,
	GOBLIN, ORC, WRAITH, GHOUL,
	IMP, RAT, CULTIST,
	# --- 13 new types from the fantasy-horror bestiary ---
	MIMIC, WOLF, WITCH, BONE_GOLEM,
	ASH_SERPENT, DAMNED_KNIGHT, MAD_WIZARD,
	DEMONIC_CROW, TENTACLE, GARGOYLE,
	WELL_SPIRIT, CURSED_BOAR, PREDATOR_FUNGUS
}

const ENEMY_TYPE_COUNT: int = 28

# Per-type sprite id (assets/sprites/<id>_sheet.png). Mirrors
# Enemy::getSpriteId() in src/Enemy.cpp line 55-89.
const SPRITE_ID := {
	EnemyType.GHOUL:           "monster_001",
	EnemyType.SPIDER:          "monster_002",
	EnemyType.WOLF:            "monster_003",
	EnemyType.CULTIST:         "monster_004",
	EnemyType.MIMIC:           "monster_005",
	EnemyType.RAT:             "monster_006",
	EnemyType.WITCH:           "monster_007",
	EnemyType.SKELETON:        "monster_008",
	EnemyType.GHOST:           "monster_009",
	EnemyType.BONE_GOLEM:      "monster_010",
	EnemyType.ASH_SERPENT:     "monster_011",
	EnemyType.DAMNED_KNIGHT:   "monster_012",
	EnemyType.MAD_WIZARD:      "monster_013",
	EnemyType.DEMONIC_CROW:    "monster_015",
	EnemyType.TENTACLE:        "monster_016",
	EnemyType.GARGOYLE:        "monster_017",
	EnemyType.WELL_SPIRIT:     "monster_018",
	EnemyType.CURSED_BOAR:     "monster_019",
	EnemyType.PREDATOR_FUNGUS: "monster_020",
	EnemyType.ZOMBIE:          "monster_021",
	EnemyType.BAT:             "monster_022",
	EnemyType.SLIME:           "monster_023",
	EnemyType.DEMON:           "monster_024",
	EnemyType.ROBOT:           "monster_025",
	EnemyType.GOBLIN:          "monster_026",
	EnemyType.ORC:             "monster_027",
	EnemyType.WRAITH:          "monster_028",
	EnemyType.IMP:             "monster_029",
}

# Per-type stats {speed, health, max_health}. Mirrors the if/else chain in
# Enemy::Enemy() constructor src/Enemy.cpp line 184-213.
const STATS := {
	EnemyType.ZOMBIE:          {"speed": 1, "health": 4, "max_health": 4},
	EnemyType.SKELETON:        {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.GHOST:           {"speed": 2, "health": 1, "max_health": 1},
	EnemyType.BAT:             {"speed": 2, "health": 1, "max_health": 1},
	EnemyType.SPIDER:         {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.SLIME:           {"speed": 1, "health": 5, "max_health": 5},
	EnemyType.DEMON:           {"speed": 1, "health": 5, "max_health": 5},
	EnemyType.ROBOT:           {"speed": 1, "health": 6, "max_health": 6},
	EnemyType.GOBLIN:         {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.ORC:             {"speed": 1, "health": 6, "max_health": 6},
	EnemyType.WRAITH:         {"speed": 2, "health": 3, "max_health": 3},
	EnemyType.GHOUL:           {"speed": 2, "health": 3, "max_health": 3},
	EnemyType.IMP:             {"speed": 2, "health": 1, "max_health": 1},
	EnemyType.RAT:             {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.CULTIST:         {"speed": 1, "health": 3, "max_health": 3},
	EnemyType.MIMIC:           {"speed": 1, "health": 4, "max_health": 4},
	EnemyType.WOLF:            {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.WITCH:           {"speed": 1, "health": 3, "max_health": 3},
	EnemyType.BONE_GOLEM:      {"speed": 1, "health": 6, "max_health": 6},
	EnemyType.ASH_SERPENT:     {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.DAMNED_KNIGHT:   {"speed": 1, "health": 5, "max_health": 5},
	EnemyType.MAD_WIZARD:      {"speed": 1, "health": 3, "max_health": 3},
	EnemyType.DEMONIC_CROW:    {"speed": 2, "health": 1, "max_health": 1},
	EnemyType.TENTACLE:        {"speed": 1, "health": 3, "max_health": 3},
	EnemyType.GARGOYLE:        {"speed": 1, "health": 5, "max_health": 5},
	EnemyType.WELL_SPIRIT:     {"speed": 2, "health": 2, "max_health": 2},
	EnemyType.CURSED_BOAR:     {"speed": 2, "health": 4, "max_health": 4},
	EnemyType.PREDATOR_FUNGUS: {"speed": 1, "health": 3, "max_health": 3},
}

# Default fallback if STATS is missing an entry (defensive programming).
const _DEFAULT_STATS := {"speed": 1, "health": 2, "max_health": 2}

# --- Anti-stuck + AI constants (mirror src/Enemy.cpp line 358-360) ----------
const STUCK_THRESHOLD_MS: int = 600        # 36 frames @ 60 FPS
const PATH_RECALC_INTERVAL_MS: int = 200   # normal BFS recalc cadence
const SHOOT_RANGE_PX: float = 500.0
const SHOOT_COOLDOWN_MIN_MS: int = 1000
const SHOOT_COOLDOWN_RAND_MS: int = 1500

# 4-connected neighbour offsets (must match BFS.gd order exactly so the
# BFS direction matches the move-greedy iteration order).
const _DC: Array[int] = [0, 1, 0, -1]
const _DR: Array[int] = [-1, 0, 1, 0]

# --- Public state -----------------------------------------------------------
var type: int = EnemyType.ZOMBIE
var speed: int = 1
var health: int = 2
var max_health: int = 2
var dx: int = 0
var dy: int = 0

# Timers (simulated ms, -16 per frame @ 60 FPS).
var path_update_timer: int = 0
var anim_time: int = 0          # NEVER reset for BFS (see Enemy.cpp:154)
var shoot_cooldown: int = 0
var attacking_timer: int = 0
var dying_timer: int = 0
var burning_timer: int = 0
var burn_anim_time: int = 0
var burned_flag: bool = false
var electrified_timer: int = 0
var electrified_anim_time: int = 0
var stuck_timer: int = 0
var last_pos: Vector2 = Vector2.ZERO

# Flee mode (chalice active): when true, enemy runs away from player.
var flee_mode: bool = false
var prev_flee_mode: bool = false

# Sprite reference (assigned in scene or via load_sprite).
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null


# ===========================================================================
# Lifecycle
# ===========================================================================

# init(type, start_col, start_row): constructor equivalent to C++
# `Enemy(EnemyType t, int startCol, int startRow)`. Call this immediately
# after instantiating the Enemy node (or after add_child).
func init(t: int, start_col: int, start_row: int) -> void:
	type = t
	# Pixel position = cell centre, offset down by UI_HEIGHT (UI bar on top).
	position = Vector2(
		start_col * TILE_SIZE + TILE_SIZE / 2.0,
		start_row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT
	)
	last_pos = position  # avoid false "stuck" detection on frame 1
	dx = 0
	dy = 0

	# Pull stats from the per-type table.
	var stats: Dictionary = STATS.get(type, _DEFAULT_STATS)
	speed = stats.speed
	health = stats.health
	max_health = stats.max_health

	# Reset all timers (constructor initializer list in C++).
	path_update_timer = 0
	anim_time = 0
	shoot_cooldown = 0
	attacking_timer = 0
	dying_timer = 0
	burning_timer = 0
	burn_anim_time = 0
	burned_flag = false
	electrified_timer = 0
	electrified_anim_time = 0
	stuck_timer = 0
	flee_mode = false
	prev_flee_mode = false


# ===========================================================================
# update_enemy(maze, player_grid_pos, player_pixel_pos, enemy_projectiles)
# Mirrors Enemy::update() in src/Enemy.cpp line 362-512.
# ===========================================================================
func update_enemy(maze: Object, player_grid_pos: Vector2i,
				  player_pixel_pos: Vector2,
				  enemy_projectiles: Array) -> void:
	# Tick animation timers (16 ms / frame @ 60 FPS).
	attacking_timer = _tick(attacking_timer)
	dying_timer = _tick(dying_timer)

	# --- Electrified state: lightning-bolt visual; enemy frozen but timer
	# still ticks so other timers progress alongside it. ---
	if electrified_timer > 0:
		if electrified_timer > 1:
			electrified_timer -= 1
		else:
			electrified_timer = 0
		electrified_anim_time += 16

	# --- Burning state: chalice fire aura, enemy frozen & silent. ---
	if burning_timer > 0:
		if burning_timer > 1:
			burning_timer -= 1
		else:
			burning_timer = 0
		burn_anim_time += 16
		return  # no movement / no shooting while burning

	# Dying animation in progress: freeze movement.
	if dying_timer > 0:
		return

	var col := int(position.x / TILE_SIZE)
	var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
	var center_x: float = col * TILE_SIZE + TILE_SIZE / 2.0
	var center_y: float = row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT
	path_update_timer += 16
	anim_time += 16  # continuous; NEVER reset here (preserves BFS cadence)

	# --- Anti-stuck tracking (line 402-415) ---
	# If the enemy barely moved (<1 px) since last frame, accumulate the
	# stuck timer; otherwise reset. When it exceeds STUCK_THRESHOLD_MS we
	# force a BFS recalc and pick a random direction as last resort.
	var dx_pos: float = position.x - last_pos.x
	var dy_pos: float = position.y - last_pos.y
	if dx_pos * dx_pos + dy_pos * dy_pos < 1.0:
		stuck_timer += 16
	else:
		stuck_timer = 0
	last_pos = position

	# When close enough to cell centre, snap and try to recalc direction.
	if absf(position.x - center_x) < speed \
			and absf(position.y - center_y) < speed:
		position.x = center_x
		position.y = center_y

		# Force path recompute on: timer expiry, idle, stuck, or flee flip.
		var flee_changed: bool = flee_mode != prev_flee_mode
		var must_recompute: bool = (path_update_timer >= PATH_RECALC_INTERVAL_MS) \
				or (dx == 0 and dy == 0) \
				or (stuck_timer > STUCK_THRESHOLD_MS) \
				or flee_changed
		prev_flee_mode = flee_mode

		if must_recompute:
			path_update_timer = 0
			var path_found: bool = false

			if flee_mode:
				# Flee: maximise distance from player. Greedy is fine here
				# (no need for shortest path - just get away).
				_flee_greedy(maze, player_grid_pos)
				if dx != 0 or dy != 0:
					path_found = true
					stuck_timer = 0
			else:
				# Chase: BFS shortest path (all enemy types use BFS).
				var next_step: Vector2i = BFS.find_path(
					maze, Vector2i(col, row), player_grid_pos)
				if next_step.x >= 0:
					dx = next_step.x - col
					dy = next_step.y - row
					path_found = true
					stuck_timer = 0
				# Fallback 1: BFS failed (rare, player unreachable) -> greedy.
				if not path_found:
					_move_greedy(maze, player_grid_pos)
					if dx != 0 or dy != 0:
						path_found = true
						stuck_timer = 0
			# Fallback 2: still no direction. Only break out if stuck.
			if not path_found and stuck_timer > STUCK_THRESHOLD_MS:
				_pick_random_open_dir(maze, col, row)
				if dx != 0 or dy != 0:
					stuck_timer = 0
			# If not stuck yet, leave dx=dy=0; will force recalc next frame
			# via the "idle" condition above.

		# Stop if the cell ahead is a wall (don't tunnel through).
		if maze.is_wall(col + dx, row + dy):
			dx = 0
			dy = 0

	position.x += dx * speed
	position.y += dy * speed

	# --- Shooting (canShoot types only) ---
	# Disabled while fleeing (chalice active - enemy runs, doesn't shoot).
	if can_shoot(type) and not flee_mode:
		if shoot_cooldown > 0:
			shoot_cooldown -= 16
		else:
			shoot_cooldown = SHOOT_COOLDOWN_MIN_MS \
					+ (randi() % SHOOT_COOLDOWN_RAND_MS)
			var dyp: float = player_pixel_pos.y - position.y
			var dxp: float = player_pixel_pos.x - position.x
			var dist: float = sqrt(dxp * dxp + dyp * dyp)
			if dist > 0.0 and dist < SHOOT_RANGE_PX:
				attacking_timer = 400  # attack animation ~400 ms
				enemy_projectiles.append({
					"pos": position,
					"dir": Vector2(dxp / dist * 3.0, dyp / dist * 3.0),
					"power": 1,
					"active": true,
					"type": 0,  # WeaponType.PISTOL appearance
				})


# ===========================================================================
# Damage / death
# ===========================================================================

# take_damage(dmg): reduce HP by `dmg`. If HP reaches 0, trigger the death
# animation (dying_timer = 600 ms ~= 6 frames at 120 ms each).
# Mirrors Enemy::takeDamage() line 516-523.
func take_damage(dmg: int) -> void:
	if dying_timer > 0:
		return  # already dying: ignore further damage
	health -= dmg
	if health <= 0:
		health = 0
		dying_timer = 600


func is_dead() -> bool:
	return health <= 0


func is_dying() -> bool:
	return dying_timer > 0


# is_death_anim_done(): true once HP <= 0 AND the death animation has
# finished (dyingTimer == 0). Game uses this to finally remove the enemy.
func is_death_anim_done() -> bool:
	return health <= 0 and dying_timer == 0


# ===========================================================================
# Burning state (player invincibility from chalice)
# ===========================================================================

# start_burning(frames): ignite the enemy for `frames` frames. While
# burning the enemy is frozen; on expiry, Game finalises the death.
# Sets burnedFlag so Game can detect the burning->death transition and
# spawn the ash pile + final FireBurst.
# Mirrors Enemy::startBurning() line 532-537.
func start_burning(frames: int = 50) -> void:
	if dying_timer > 0 or burning_timer > 0:
		return
	burning_timer = frames
	burn_anim_time = 0
	burned_flag = true


func is_burning() -> bool:
	return burning_timer > 0


func was_burned() -> bool:
	return burned_flag


func clear_burned_flag() -> void:
	burned_flag = false


# ===========================================================================
# Electrified state (lightning bolt from Magic Scepter)
# ===========================================================================

# start_electrified(frames): shock the enemy for `frames` frames. Visual
# overlay of blue-white electric arcs. Does NOT kill the enemy - damage
# is applied by Game (the bolt itself).
# Mirrors Enemy::startElectrified() line 545-548.
func start_electrified(frames: int = 30) -> void:
	electrified_timer = frames
	electrified_anim_time = 0


func is_electrified() -> bool:
	return electrified_timer > 0


# ===========================================================================
# Flee mode (chalice of immortality active)
# ===========================================================================

func set_flee_mode(flee: bool) -> void:
	flee_mode = flee


func is_fleeing() -> bool:
	return flee_mode


# ===========================================================================
# AI helpers (private)
# ===========================================================================

# _move_greedy(maze, target): pick the adjacent cell minimising squared
# distance to target, with a +10 penalty for backtracking. If no cell
# improves the distance (dead-end), fall back to a random open direction.
# Mirrors Enemy::moveGreedy() line 252-277.
func _move_greedy(maze: Object, target: Vector2i) -> void:
	var col := int(position.x / TILE_SIZE)
	var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
	var best_dx: int = 0
	var best_dy: int = 0
	var min_dist: float = 999999.0
	var any_open: bool = false
	for i in range(4):
		var nc: int = col + _DC[i]
		var nr: int = row + _DR[i]
		if not maze.is_wall(nc, nr):
			any_open = true
			var dist: float = float((nc - target.x) * (nc - target.x)
					+ (nr - target.y) * (nr - target.y))
			# Penalise reversing direction (+10 dist).
			if _DC[i] == -dx and _DR[i] == -dy:
				dist += 10.0
			if dist < min_dist:
				min_dist = dist
				best_dx = _DC[i]
				best_dy = _DR[i]
	# Dead-end fallback: pick a random open direction.
	if any_open and best_dx == 0 and best_dy == 0:
		_pick_random_open_dir(maze, col, row)
		return
	dx = best_dx
	dy = best_dy


# _flee_greedy(maze, target): opposite of greedy - pick the adjacent
# cell that MAXIMISES distance from the player, with a -10 penalty for
# running TOWARDS the player. If all directions are penalised to zero,
# fall back to a random open direction.
# Mirrors Enemy::fleeGreedy() line 284-312.
func _flee_greedy(maze: Object, target: Vector2i) -> void:
	var col := int(position.x / TILE_SIZE)
	var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
	var best_dx: int = 0
	var best_dy: int = 0
	var max_dist: float = -1.0  # we want to MAXIMISE distance
	var any_open: bool = false
	for i in range(4):
		var nc: int = col + _DC[i]
		var nr: int = row + _DR[i]
		if not maze.is_wall(nc, nr):
			any_open = true
			var dist: float = float((nc - target.x) * (nc - target.x)
					+ (nr - target.y) * (nr - target.y))
			# Penalise moving toward the player (reverse direction).
			if _DC[i] == -dx and _DR[i] == -dy:
				dist -= 10.0
			if dist > max_dist:
				max_dist = dist
				best_dx = _DC[i]
				best_dy = _DR[i]
	if not any_open:
		dx = 0
		dy = 0
		return
	if best_dx == 0 and best_dy == 0:
		_pick_random_open_dir(maze, col, row)
		return
	dx = best_dx
	dy = best_dy


# _pick_random_open_dir(maze, col, row): pick one of the 4 cardinal
# directions whose adjacent cell is not a wall, starting from a random
# offset so there's no directional bias. Returns true if found.
# Mirrors Enemy::pickRandomOpenDir() line 319-333.
func _pick_random_open_dir(maze: Object, col: int, row: int) -> bool:
	var start: int = randi() % 4
	for i in range(4):
		var idx: int = (start + i) % 4
		var nc: int = col + _DC[idx]
		var nr: int = row + _DR[idx]
		if not maze.is_wall(nc, nr):
			dx = _DC[idx]
			dy = _DR[idx]
			return true
	dx = 0
	dy = 0
	return false


# ===========================================================================
# Static helpers (mirror Enemy.cpp static methods)
# ===========================================================================

# can_shoot(t): true for ranged enemy types (skeleton/cultist/demon/
# wraith/robot/witch/mad_wizard). Mirrors Enemy::canShoot() line 108-121.
static func can_shoot(t: int) -> bool:
	return t == EnemyType.SKELETON \
			or t == EnemyType.CULTIST \
			or t == EnemyType.DEMON \
			or t == EnemyType.WRAITH \
			or t == EnemyType.ROBOT \
			or t == EnemyType.WITCH \
			or t == EnemyType.MAD_WIZARD


# uses_bfs(t): kept for parity with the C++ API. All enemy types use BFS
# in the current build; this is preserved for future rebalancing hooks.
static func uses_bfs(_t: int) -> bool:
	return true


# get_sprite_id(t): returns the file id ("monster_001".."monster_029") for
# this enemy type, or "" if no sprite is mapped. Mirrors Enemy::getSpriteId.
static func get_sprite_id(t: int) -> String:
	return SPRITE_ID.get(t, "")


# ===========================================================================
# Accessors
# ===========================================================================

func get_grid_pos() -> Vector2i:
	return Vector2i(
		int(position.x / TILE_SIZE),
		int((position.y - UI_HEIGHT) / TILE_SIZE)
	)

func get_pixel_pos() -> Vector2:
	return position

func get_type() -> int:
	return type


# ===========================================================================
# Internal helpers
# ===========================================================================

# _tick(t): decrement a simulated-ms timer by 16 ms, floored at 0.
# Matches the `if (t > 16) t -= 16; else t = 0;` idiom in Enemy.cpp.
static func _tick(t: int) -> int:
	return t - 16 if t > 16 else 0

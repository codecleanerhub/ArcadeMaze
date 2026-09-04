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
        EnemyType.ZOMBIE:          {"speed": 1, "health": 4, "max_health": 4, "color": Color(0.4, 0.5, 0.3), "accent": Color(0.6, 0.7, 0.4)},
        EnemyType.SKELETON:        {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.8, 0.8, 0.7), "accent": Color(0.5, 0.5, 0.4)},
        EnemyType.GHOST:           {"speed": 2, "health": 1, "max_health": 1, "color": Color(0.7, 0.8, 0.9, 0.6), "accent": Color(1.0, 1.0, 1.0, 0.5)},
        EnemyType.BAT:             {"speed": 2, "health": 1, "max_health": 1, "color": Color(0.3, 0.2, 0.4), "accent": Color(0.6, 0.4, 0.7)},
        EnemyType.SPIDER:         {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.2, 0.1, 0.1), "accent": Color(0.8, 0.2, 0.2)},
        EnemyType.SLIME:           {"speed": 1, "health": 5, "max_health": 5, "color": Color(0.3, 0.7, 0.3), "accent": Color(0.5, 0.9, 0.5)},
        EnemyType.DEMON:           {"speed": 1, "health": 5, "max_health": 5, "color": Color(0.6, 0.1, 0.1), "accent": Color(1.0, 0.4, 0.1)},
        EnemyType.ROBOT:           {"speed": 1, "health": 6, "max_health": 6, "color": Color(0.5, 0.5, 0.6), "accent": Color(0.8, 0.8, 0.9)},
        EnemyType.GOBLIN:         {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.4, 0.6, 0.2), "accent": Color(0.6, 0.8, 0.3)},
        EnemyType.ORC:             {"speed": 1, "health": 6, "max_health": 6, "color": Color(0.5, 0.4, 0.2), "accent": Color(0.7, 0.5, 0.3)},
        EnemyType.WRAITH:         {"speed": 2, "health": 3, "max_health": 3, "color": Color(0.3, 0.2, 0.4, 0.7), "accent": Color(0.6, 0.4, 0.8, 0.8)},
        EnemyType.GHOUL:           {"speed": 2, "health": 3, "max_health": 3, "color": Color(0.5, 0.4, 0.3), "accent": Color(0.7, 0.5, 0.4)},
        EnemyType.IMP:             {"speed": 2, "health": 1, "max_health": 1, "color": Color(0.7, 0.2, 0.3), "accent": Color(1.0, 0.5, 0.3)},
        EnemyType.RAT:             {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.4, 0.3, 0.2), "accent": Color(0.6, 0.5, 0.3)},
        EnemyType.CULTIST:         {"speed": 1, "health": 3, "max_health": 3, "color": Color(0.3, 0.1, 0.3), "accent": Color(0.6, 0.2, 0.6)},
        EnemyType.MIMIC:           {"speed": 1, "health": 4, "max_health": 4, "color": Color(0.6, 0.5, 0.2), "accent": Color(0.4, 0.3, 0.1)},
        EnemyType.WOLF:            {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.3, 0.3, 0.3), "accent": Color(0.6, 0.5, 0.4)},
        EnemyType.WITCH:           {"speed": 1, "health": 3, "max_health": 3, "color": Color(0.2, 0.1, 0.3), "accent": Color(0.5, 0.2, 0.7)},
        EnemyType.BONE_GOLEM:      {"speed": 1, "health": 6, "max_health": 6, "color": Color(0.9, 0.9, 0.8), "accent": Color(0.6, 0.6, 0.5)},
        EnemyType.ASH_SERPENT:     {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.3, 0.3, 0.2), "accent": Color(0.5, 0.5, 0.3)},
        EnemyType.DAMNED_KNIGHT:   {"speed": 1, "health": 5, "max_health": 5, "color": Color(0.2, 0.2, 0.3), "accent": Color(0.5, 0.3, 0.3)},
        EnemyType.MAD_WIZARD:      {"speed": 1, "health": 3, "max_health": 3, "color": Color(0.3, 0.2, 0.5), "accent": Color(0.6, 0.4, 0.9)},
        EnemyType.DEMONIC_CROW:    {"speed": 2, "health": 1, "max_health": 1, "color": Color(0.1, 0.1, 0.1), "accent": Color(0.4, 0.3, 0.3)},
        EnemyType.TENTACLE:        {"speed": 1, "health": 3, "max_health": 3, "color": Color(0.4, 0.2, 0.4), "accent": Color(0.7, 0.3, 0.7)},
        EnemyType.GARGOYLE:        {"speed": 1, "health": 5, "max_health": 5, "color": Color(0.4, 0.4, 0.5), "accent": Color(0.6, 0.6, 0.7)},
        EnemyType.WELL_SPIRIT:     {"speed": 2, "health": 2, "max_health": 2, "color": Color(0.3, 0.5, 0.7, 0.6), "accent": Color(0.5, 0.7, 0.9, 0.7)},
        EnemyType.CURSED_BOAR:     {"speed": 2, "health": 4, "max_health": 4, "color": Color(0.4, 0.2, 0.2), "accent": Color(0.6, 0.3, 0.3)},
        EnemyType.PREDATOR_FUNGUS: {"speed": 1, "health": 3, "max_health": 3, "color": Color(0.5, 0.3, 0.2), "accent": Color(0.7, 0.5, 0.3)},
}

# Default fallback if STATS is missing an entry (defensive programming).
const _DEFAULT_STATS := {"speed": 1, "health": 2, "max_health": 2, "color": Color(0.6, 0.4, 0.3), "accent": Color(0.9, 0.7, 0.5)}

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

# Sprite sheet loaded from SpriteManager (AI-generated sprite).
var _sprite_sheet: Object = null  # SpriteManager.Sheet
var _sprite_loaded: bool = false
var _sprite_id: String = ""


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

        # Load the AI-generated sprite sheet for this enemy type.
        _load_sprite()


# Load the sprite sheet via SpriteManager. The sprite is then rendered in
# _draw() using the correct animation frame. If no sprite is mapped for
# this enemy type, _sprite_loaded stays false and _draw() falls back to
# procedural rendering (circle + eyes).
func _load_sprite() -> void:
        _sprite_id = get_sprite_id(type)
        if _sprite_id.is_empty():
                _sprite_loaded = false
                return
        if SpriteManager:
                _sprite_sheet = SpriteManager.get_sheet(_sprite_id)
                _sprite_loaded = _sprite_sheet != null and _sprite_sheet.is_loaded()


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

        # Trigger redraw so the sprite animation updates each frame.
        queue_redraw()


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
                # Spawn particle explosion (Godot-native effect, non in C++)
                if EffectsManager:
                        var p := EffectsManager.spawn_explosion(position,
                                Color(0.8, 0.2, 0.1), 25, 0.6)
                        if get_parent():
                                get_parent().add_child(p)
                        EffectsManager.screen_shake(4.0, 0.2)


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
        # Applica shader fuoco (Godot-native, non in C++)
        if EffectsManager and sprite:
                EffectsManager.set_burn_effect(sprite, true)


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
        # Applica shader lightning (Godot-native, non in C++)
        if EffectsManager and sprite:
                EffectsManager.set_electrified_effect(sprite, true)


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
# Rendering: _draw() renders the enemy.
# When a sprite is loaded (AI-generated PNG), we render the correct animation
# frame via draw_texture_rect. Otherwise we fall back to procedural shapes
# (circle + eyes) so the game is still playable if assets are missing.
# ===========================================================================
func _draw() -> void:
        # If dying, draw death animation (expanding circle)
        if is_dying():
                var progress: float = 1.0 - float(dying_timer) / 60.0
                var radius: float = 16.0 + progress * 20.0
                draw_circle(Vector2.ZERO, radius,
                        Color(1.0, 0.3, 0.1, 1.0 - progress))
                return

        # --- PRIMARY: render AI-generated sprite if loaded ---
        if _sprite_loaded and _sprite_sheet != null:
                _draw_sprite_frame()
                # Overlay effects on top of the sprite
                if is_burning():
                        draw_circle(Vector2.ZERO, 20.0, Color(1.0, 0.4, 0.0, 0.5))
                        draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.8, 0.2, 0.7))
                if is_electrified():
                        for i in range(4):
                                var angle: float = i * PI / 2.0 + anim_time * 0.1
                                var p1: Vector2 = Vector2(cos(angle), sin(angle)) * 16.0
                                var p2: Vector2 = Vector2(cos(angle + 0.5), sin(angle + 0.5)) * 22.0
                                draw_line(p1, p2, Color(0.3, 0.7, 1.0, 0.9), 2.0)
                # Health bar above enemy (only if damaged)
                if health < max_health and not is_dead():
                        var bar_w: float = 24.0
                        var bar_h: float = 3.0
                        var bar_y: float = -28.0
                        draw_rect(Rect2(-bar_w / 2, bar_y, bar_w, bar_h),
                                Color(0.2, 0.0, 0.0, 0.8), true)
                        var hp_ratio: float = float(health) / float(max_health)
                        draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_ratio, bar_h),
                                Color(1.0, 0.3, 0.1, 1.0), true)
                return

        # --- FALLBACK: procedural rendering (circle + eyes) when no sprite ---
        # If burning, draw flame overlay
        if is_burning():
                draw_circle(Vector2.ZERO, 20.0, Color(1.0, 0.4, 0.0, 0.6))
                draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.8, 0.2, 0.8))

        # If electrified, draw electric arcs
        if is_electrified():
                for i in range(4):
                        var angle: float = i * PI / 2.0 + anim_time * 0.1
                        var p1: Vector2 = Vector2(cos(angle), sin(angle)) * 16.0
                        var p2: Vector2 = Vector2(cos(angle + 0.5), sin(angle + 0.5)) * 22.0
                        draw_line(p1, p2, Color(0.3, 0.7, 1.0, 0.9), 2.0)

        # Draw enemy body (procedural fallback based on type)
        var stats: Dictionary = STATS.get(type, _DEFAULT_STATS)
        var body_color: Color = stats.get("color", Color(0.6, 0.4, 0.3))
        var accent_color: Color = stats.get("accent", Color(0.9, 0.7, 0.5))

        # Main body circle
        draw_circle(Vector2.ZERO, 16.0, body_color)
        draw_circle(Vector2.ZERO, 12.0, accent_color)

        # Eyes (facing direction)
        var eye_offset: Vector2 = Vector2(dx, dy) * 4.0
        draw_circle(Vector2(-4, -2) + eye_offset, 2.0, Color.WHITE)
        draw_circle(Vector2(4, -2) + eye_offset, 2.0, Color.WHITE)
        draw_circle(Vector2(-4, -2) + eye_offset, 1.0, Color.BLACK)
        draw_circle(Vector2(4, -2) + eye_offset, 1.0, Color.BLACK)

        # Health bar above enemy
        if health < max_health and not is_dead():
                var bar_w2: float = 24.0
                var bar_h2: float = 3.0
                var bar_y2: float = -22.0
                draw_rect(Rect2(-bar_w2 / 2, bar_y2, bar_w2, bar_h2),
                        Color(0.2, 0.0, 0.0, 0.8), true)
                var hp_ratio2: float = float(health) / float(max_health)
                draw_rect(Rect2(-bar_w2 / 2, bar_y2, bar_w2 * hp_ratio2, bar_h2),
                        Color(1.0, 0.3, 0.1, 1.0), true)

        # Flee mode indicator (fear exclamation mark)
        if flee_mode:
                draw_string(get_theme_default_font(), Vector2(-3, -24),
                        "!", HORIZONTAL_ALIGNMENT_CENTER, 16, Color(1, 1, 0, 0.9))


# Draw the current animation frame from the AI-generated sprite sheet.
# Mirrors C++ Enemy::draw() which uses SpriteSheet::getFrameTexture.
func _draw_sprite_frame() -> void:
        if not _sprite_loaded or _sprite_sheet == null:
                return
        # Determine animation name and frame index.
        # Priority: walk (if moving) > idle (default).
        var anim_name: String = "idle"
        var frame: int = 0
        var is_moving: bool = (dx != 0 or dy != 0) and not is_burning() and not is_electrified()
        if is_moving:
                anim_name = "walk"
        # Get frame count for the chosen animation; fall back to idle.
        var fc: int = _sprite_sheet.get_frame_count(anim_name)
        if fc == 0:
                anim_name = "idle"
                fc = _sprite_sheet.get_frame_count("idle")
        if fc > 0:
                var frame_duration: int = 200  # ms per frame (matches metadata)
                frame = (int(anim_time) / frame_duration) % fc
        # Get the AtlasTexture for this frame.
        var at: AtlasTexture = _sprite_sheet.get_frame_texture(anim_name, frame)
        if at == null:
                return
        # Draw centered, with slight vertical bob when walking.
        var tw: float = at.get_width()
        var th: float = at.get_height()
        var bob_y: float = 0.0
        if is_moving:
                bob_y = sin(float(anim_time) * 0.01) * 2.0
        var draw_pos: Vector2 = Vector2(-tw * 0.5, -th * 0.5 + bob_y)
        # Flip horizontally if facing left (dx < 0).
        var dest_rect: Rect2 = Rect2(draw_pos, Vector2(tw, th))
        if dx < 0:
                # Flip by drawing with reversed source rect.
                var flipped_at := AtlasTexture.new()
                flipped_at.atlas = at.atlas
                flipped_at.region = Rect2(
                        at.region.position.x + at.region.size.x,
                        at.region.position.y,
                        -at.region.size.x,
                        at.region.size.y
                )
                draw_texture_rect(flipped_at, dest_rect, false)
        else:
                draw_texture_rect(at, dest_rect, false)


# ===========================================================================
# Internal helpers
# ===========================================================================

# _tick(t): decrement a simulated-ms timer by 16 ms, floored at 0.
# Matches the `if (t > 16) t -= 16; else t = 0;` idiom in Enemy.cpp.
static func _tick(t: int) -> int:
        return t - 16 if t > 16 else 0

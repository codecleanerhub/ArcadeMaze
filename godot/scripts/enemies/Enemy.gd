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
var _burn_effect_sheet: Object = null  # SpriteManager.Sheet for burning effect

# --- DeformableSprite (replaces the 4-frame cycle that produced the
#     "disjointed gif" effect with HD sheets) ---
# The HD sheets are single AI drawings carved into 4x4 grids. Cycling through
# 4 horizontal slices of one image looked like a broken gif. DeformableSprite
# takes ONE frame and deforms an 8x8 mesh in real time (IDLE/WALK/ATTACK),
# matching the C++ architecture (Boss.cpp uses the same approach).
var _deform_sprite: DeformableSprite = null
var _deform_loaded: bool = false
# SD sheet cache (forzata per evitare HD gif scollegata)
var _sd_sheet: Object = null
# Per-enemy accent color for the walk_cycle shader (warm pulse).
var _accent_color: Color = Color(1.0, 0.5, 0.2, 1.0)
# Dust puff spawn counter (every Nth frame while walking, spawn a puff).
var _dust_frame_counter: int = 0
const DUST_PUFF_INTERVAL: int = 6  # spawn a puff every 6 frames (~100ms @ 60fps)


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

        # Load effect spritesheet for burning overlay
        _burn_effect_sheet = null
        if SpriteManager:
                _burn_effect_sheet = SpriteManager.get_sheet("effect_fireaura")

        # Apply CharacterArt enhancement shader (Godot-native sprite enhancement)
        if CharacterArt and sprite:
                CharacterArt.apply_enhancement(sprite, false)

        # Cache accent color from STATS for walk_cycle shader tinting.
        var stats: Dictionary = STATS.get(type, _DEFAULT_STATS)
        _accent_color = stats.get("accent", _accent_color)

        # --- DeformableSprite setup ---
        # FIX (lag/movimenti rallentati): DeformableSprite._sync_mesh() fa
        # surface_remove + add_surface_from_arrays ogni frame per ogni nemico,
        # che è ESTREMAMENTE lento (specialmente su GPU entry-level come
        # NVIDIA 940M). Disabilitiamo DeformableSprite per i nemici e torniamo
        # al frame cycling del SD sheet (che è un vero walk cycle connesso,
        # generato da gen_deterministic_walk.py). Forziamo SD sheet (non HD)
        # perché le HD sheet sono singole immagini AI divise in 4x4 fasce
        # che producono l'effetto "gif animata scollegata".
        # _ensure_deform_sprite()  # DISABILITATO per performance
        _deform_loaded = false
        # Forza SD sheet: richiedi esplicitamente la versione SD via SpriteManager
        if SpriteManager and not _sprite_id.is_empty():
                # SpriteManager preferisce HD se esiste; per i nemici vogliamo SD.
                # Simuliamo la SD sheet leggendo direttamente il file PNG.
                pass  # _draw_sprite_frame userà _sprite_sheet (che è già SD o HD)
        # Apply CharacterArt enhancement shader (Godot-native sprite enhancement)
        # già applicato sopra.


# Lazily create the DeformableSprite child node.
func _ensure_deform_sprite() -> void:
        if _deform_sprite != null:
                return
        var ds := DeformableSprite.new()
        add_child(ds)
        _deform_sprite = ds


# Load the SD version of a sprite sheet (256x64 = 4 frame walk cycle).
# Used to avoid the HD "gif scollegata" effect: HD sheets are single AI
# drawings carved into 4x4 grids, while SD sheets are true walk cycles
# generated by gen_deterministic_walk.py.
func _load_sd_sheet(sprite_id: String) -> Object:
        var sd_path := "res://assets/sprites/" + sprite_id + "_sheet.png"
        if not ResourceLoader.exists(sd_path):
                return null
        var tex := load(sd_path) as Texture2D
        if tex == null:
                return null
        # Build a Sheet-like object inline (mirror SpriteManager.Sheet).
        var sheet := SpriteManager.Sheet.new()
        sheet.texture = tex
        sheet.frame_w = 64
        sheet.frame_h = 64
        sheet.columns = 4
        sheet.rows = 1
        sheet.animations["idle"] = {"row": 0, "frames": 4, "frameDuration": 200}
        sheet.animations["walk"] = {"row": 0, "frames": 4, "frameDuration": 100}
        sheet.animations["attack"] = {"row": 0, "frames": 4, "frameDuration": 90}
        sheet.animations["death"] = {"row": 0, "frames": 1, "frameDuration": 120}
        return sheet


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
        # --- PRIMARY: render AI-generated sprite if loaded ---
        # _draw_sprite_frame() handles death/attack/walk/idle animations
        if _sprite_loaded and _sprite_sheet != null:
                _draw_sprite_frame()
                # Overlay effects on top of the sprite
                if is_burning():
                        # Draw fire aura spritesheet if loaded
                        if _burn_effect_sheet != null and _burn_effect_sheet.is_loaded():
                                var burn_progress: float = 1.0 - float(burning_timer) / 50.0
                                var burn_frame: int = int(burn_progress * 4) % 4
                                var burn_at: AtlasTexture = _burn_effect_sheet.get_frame_texture("idle", burn_frame)
                                if burn_at != null:
                                        draw_texture_rect(burn_at, Rect2(-24, -24, 48, 48), false)
                        else:
                                # Fallback: simple flame circles
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
                        var hp_col: Color = Color(0.86, 0.16, 0.16)  # red < 25%
                        if hp_ratio > 0.5:
                                hp_col = Color(0.31, 0.86, 0.31)  # green > 50%
                        elif hp_ratio > 0.25:
                                hp_col = Color(0.86, 0.71, 0.16)  # yellow 25-50%
                        draw_rect(Rect2(-bar_w / 2, bar_y, bar_w * hp_ratio, bar_h), hp_col, true)
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

        # Type-specific procedural details (28 unique fallbacks).
        # Mirrors Enemy::renderPrimitives() in src/Enemy.cpp line 885-1449.
        _draw_primitive_fallback()

        # Health bar above enemy
        if health < max_health and not is_dead():
                var bar_w2: float = 24.0
                var bar_h2: float = 3.0
                var bar_y2: float = -22.0
                draw_rect(Rect2(-bar_w2 / 2, bar_y2, bar_w2, bar_h2),
                        Color(0.2, 0.0, 0.0, 0.8), true)
                var hp_ratio2: float = float(health) / float(max_health)
                var hp_col2: Color = Color(0.86, 0.16, 0.16)  # red < 25%
                if hp_ratio2 > 0.5:
                        hp_col2 = Color(0.31, 0.86, 0.31)  # green > 50%
                elif hp_ratio2 > 0.25:
                        hp_col2 = Color(0.86, 0.71, 0.16)  # yellow 25-50%
                draw_rect(Rect2(-bar_w2 / 2, bar_y2, bar_w2 * hp_ratio2, bar_h2), hp_col2, true)

        # Flee mode indicator (fear exclamation mark - rendered as yellow triangle)
        if flee_mode:
                # Simple yellow "!" indicator drawn as triangle + circle
                var excl_color := Color(1.0, 1.0, 0.0, 0.9)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(-3.0, -28.0),
                        Vector2(3.0, -28.0),
                        Vector2(0.0, -18.0),
                ]), excl_color)
                draw_circle(Vector2(0.0, -14.0), 2.0, excl_color)


# Draw the current animation frame from the AI-generated sprite sheet.
# Mirrors C++ Enemy::draw() which uses SpriteSheet::getFrameTexture.
#
# FIX (gif-animata-scollegata bug):
# When the DeformableSprite is loaded (preferred path), we delegate the
# rendering to it and only update its animation mode + the walk_cycle shader
# uniforms. This produces smooth 60fps mesh deformation of a single frame
# instead of cycling through 4 horizontal slices of an HD AI drawing.
# The old AtlasTexture frame-cycling path is kept as a fallback for cases
# where the SD sheet can't be loaded.
func _draw_sprite_frame() -> void:
        # Update the DeformableSprite if loaded (preferred path).
        if _deform_loaded and _deform_sprite != null:
                _update_deform_sprite_animation()
                # The deform sprite draws itself via MeshInstance2D; we don't
                # need to call draw_texture_rect here. But we DO need to draw
                # the burning/electrified overlays and the HP bar.
                # The walk_cycle shader update happens via EffectsManager.
                var is_moving: bool = (dx != 0 or dy != 0) and not is_burning() and not is_electrified() and not is_dying()
                var walk_phase: float = 1.0 if is_moving else 0.0
                if EffectsManager:
                        EffectsManager.update_walk_cycle(self, walk_phase,
                                dx >= 0, anim_time * 0.001, 8.0)
                # Spawn dust puff periodically while walking.
                if is_moving:
                        _dust_frame_counter += 1
                        if _dust_frame_counter >= DUST_PUFF_INTERVAL:
                                _dust_frame_counter = 0
                                _spawn_dust_puff_if_possible()
                else:
                        _dust_frame_counter = 0
                return

        # --- Fallback: AtlasTexture frame cycling (HD/SD sheet) ---
        if not _sprite_loaded or _sprite_sheet == null:
                return
        # FIX (gif animata scollegata): le HD sheet sono singole immagini AI
        # divise in 4x4 fasce → il frame cycle mostra 4 slice dello stesso
        # disegno. Usiamo la SD sheet (256x64 = 4 frame vero walk cycle)
        # caricandola direttamente se la HD è stata caricata da SpriteManager.
        var active_sheet: Object = _sprite_sheet
        if _sprite_sheet.rows == 4 and _sprite_sheet.columns == 4:
                # HD sheet: cerca di caricare la SD sheet
                if _sd_sheet == null:
                        _sd_sheet = _load_sd_sheet(_sprite_id)
                if _sd_sheet != null:
                        active_sheet = _sd_sheet
        if active_sheet == null:
                active_sheet = _sprite_sheet
        # Determine animation name and frame index.
        # Priority: death > attack > walk > idle (mirror C++ Enemy::draw)
        var anim_name: String = "idle"
        var frame: int = 0
        var frame_duration: int = 200  # ms per frame
        var is_moving2: bool = (dx != 0 or dy != 0) and not is_burning() and not is_electrified()
        # Death animation (6 frames @ 120ms)
        if is_dying():
                anim_name = "death"
                frame_duration = 120
                var fc_death: int = active_sheet.get_frame_count("death")
                if fc_death > 0:
                        var elapsed_death: int = 600 - dying_timer
                        frame = clampi(elapsed_death / frame_duration, 0, fc_death - 1)
                else:
                        _draw_death_fallback()
                        return
        # Attack animation (6 frames @ 100ms)
        elif attacking_timer > 0 and active_sheet.get_frame_count("attack") > 0:
                anim_name = "attack"
                frame_duration = 100
                var fc_attack: int = active_sheet.get_frame_count("attack")
                var elapsed_attack: int = 400 - attacking_timer
                frame = clampi(elapsed_attack / frame_duration, 0, fc_attack - 1)
        # Walk animation (6 frames @ 100ms with bob)
        elif is_moving2 and active_sheet.get_frame_count("walk") > 0:
                anim_name = "walk"
                frame_duration = 100
                var fc_walk: int = active_sheet.get_frame_count("walk")
                frame = (int(anim_time) / frame_duration) % fc_walk
        # Idle (frame 0 fisso, come C++ che evita separazione busto/bacino)
        else:
                anim_name = "idle"
                frame_duration = 200
                frame = 0  # SEMPRE frame 0 (non cycling)
        # Get the AtlasTexture for this frame.
        var at: AtlasTexture = active_sheet.get_frame_texture(anim_name, frame)
        if at == null:
                # Fallback: try idle frame 0
                at = active_sheet.get_frame_texture("idle", 0)
                if at == null:
                        return
        # Draw centered at enemy size (84x84 = 64*1.3, matches player scale).
        var target_size: float = 84.0
        var tw: float = target_size
        var th: float = target_size
        var bob_y: float = 0.0
        if is_moving2:
                bob_y = sin(float(anim_time) * 0.01) * 2.0
        var draw_pos: Vector2 = Vector2(-tw * 0.5, -th * 0.5 + bob_y)
        # Flip horizontally if facing left (dx < 0).
        # Godot 4.7 draw_texture_rect: max 5 args (texture, rect, tile, modulate, transpose)
        # For horizontal flip, use transpose=false and draw normally (flip is visual-only).
        var dest_rect: Rect2 = Rect2(draw_pos, Vector2(tw, th))
        if dx < 0:
                # Flip by drawing with transpose (mirrors X when used on AtlasTexture)
                draw_texture_rect(at, dest_rect, false, Color.WHITE, true)
        else:
                draw_texture_rect(at, dest_rect, false)


# Update the DeformableSprite's animation mode based on current state.
# Priority: death > attack > walk > idle (mirrors C++ Enemy::draw).
func _update_deform_sprite_animation() -> void:
        if _deform_sprite == null:
                return
        var mode: int = DeformableSprite.AnimMode.IDLE
        # FIX (nemici troppo piccoli): scale 1.3 (come il player) per riempire
        # meglio il tile 48px. 64*1.3=83px.
        var scale_val: float = 1.3
        var flipped: bool = dx < 0
        if is_dying():
                # DeformableSprite has no "death" mode; use IDLE with a fade-out
                # handled separately. The death fallback draws an explosion circle.
                mode = DeformableSprite.AnimMode.IDLE
        elif attacking_timer > 0:
                mode = DeformableSprite.AnimMode.ATTACK
        elif (dx != 0 or dy != 0) and not is_burning() and not is_electrified():
                mode = DeformableSprite.AnimMode.WALK
        else:
                mode = DeformableSprite.AnimMode.IDLE
        # Position: deform sprite is centered on the enemy position (already
        # offset by -32,-32 in _load_sprite). The bob is added here.
        var bob_y: float = 0.0
        if mode == DeformableSprite.AnimMode.WALK:
                bob_y = sin(float(anim_time) * 0.01) * 2.0
        # Center the deform sprite on the enemy position.
        # Sprite is 64x64 scaled by scale_val → visual size = 64*scale_val.
        # Offset = -(visual_size)/2 = -32*scale_val.
        _deform_sprite.position = Vector2(-32.0 * scale_val, -32.0 * scale_val + bob_y)
        _deform_sprite.update(float(anim_time) * 0.001, mode, scale_val, flipped)


# Spawn a dust puff at the enemy's feet (called every Nth frame while walking).
# The puff is added as a sibling of the enemy (to the parent scene tree) so
# it persists after the enemy moves on. The puff auto-frees after its lifetime.
func _spawn_dust_puff_if_possible() -> void:
        if EffectsManager == null:
                return
        var parent_node: Node = get_parent()
        if parent_node == null:
                return
        var puff: GPUParticles2D = EffectsManager.spawn_dust_puff(
                position + Vector2(0, 14.0),  # at the enemy's feet
                _accent_color)
        if puff != null:
                parent_node.add_child(puff)
                # Auto-free after the puff's lifetime (0.4s + safety margin).
                # Use a callable bound to the puff reference; Godot 4.7's
                # SceneTreeTimer.timeout signal accepts any Callable.
                var timer: SceneTreeTimer = get_tree().create_timer(0.6)
                timer.timeout.connect(_on_dust_puff_timeout.bind(puff))


# Bound callback for the dust puff auto-free timer.
func _on_dust_puff_timeout(puff: GPUParticles2D) -> void:
        if is_instance_valid(puff):
                puff.queue_free()
                if EffectsManager:
                        EffectsManager.notify_dust_puff_freed()


# ===========================================================================
# Internal helpers
# ===========================================================================

# _tick(t): decrement a simulated-ms timer by 16 ms, floored at 0.
# Matches the `if (t > 16) t -= 16; else t = 0;` idiom in Enemy.cpp.
static func _tick(t: int) -> int:
        return t - 16 if t > 16 else 0


# Death animation fallback when sprite sheet has no "death" animation.
# Draws an expanding fading circle (mirror C++ primitive fallback).
func _draw_death_fallback() -> void:
        var progress: float = 1.0 - float(dying_timer) / 600.0
        var radius: float = 16.0 + progress * 20.0
        draw_circle(Vector2.ZERO, radius,
                Color(1.0, 0.3, 0.1, 1.0 - progress))
        # Inner brighter circle
        draw_circle(Vector2.ZERO, radius * 0.6,
                Color(1.0, 0.6, 0.2, (1.0 - progress) * 0.7))


# ===========================================================================
# _draw_primitive_fallback(): type-specific procedural details drawn ON TOP
# of the base circle + eyes. Each of the 28 enemy types gets unique
# distinguishing features (arms, horns, wings, ears, hat, etc.) so the
# fallback is still readable when the AI-generated sprite sheet is missing.
# Mirrors Enemy::renderPrimitives() in src/Enemy.cpp line 885-1449.
# ===========================================================================
func _draw_primitive_fallback() -> void:
        match type:
                EnemyType.ZOMBIE:
                        # Braccia verdi penzolanti + gamba
                        draw_rect(Rect2(-18, -2, 12, 8), Color(0.39, 0.59, 0.31))
                        draw_rect(Rect2(6, -2, 12, 8), Color(0.39, 0.59, 0.31))
                        draw_rect(Rect2(-8, 8, 8, 12), Color(0.24, 0.31, 0.16))
                EnemyType.SKELETON:
                        # Arco convesso + freccia
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -8), Vector2(14, -4),
                                Vector2(12, 8), Vector2(6, 4),
                        ]), Color(0.55, 0.27, 0.07))
                        draw_rect(Rect2(-2, -1, 16, 1), Color(0.9, 0.9, 0.85))
                EnemyType.GHOST:
                        # Corpoco trasparente fluttuante: wisps sotto
                        draw_circle(Vector2(-8, 14), 4, Color(0.59, 0.78, 1.0, 0.4))
                        draw_circle(Vector2(8, 14), 4, Color(0.59, 0.78, 1.0, 0.4))
                        draw_circle(Vector2(0, 16), 4, Color(0.59, 0.78, 1.0, 0.4))
                EnemyType.BAT:
                        # Ali (quadrilateri simili a ventagli)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -4), Vector2(-20, -8),
                                Vector2(-16, 4), Vector2(-4, 4),
                        ]), Color(0.31, 0.0, 0.31))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(2, -4), Vector2(20, -8),
                                Vector2(16, 4), Vector2(4, 4),
                        ]), Color(0.31, 0.0, 0.31))
                EnemyType.SPIDER:
                        # 8 zampe (4 per lato)
                        for i in 4:
                                var y_off: float = -2.0 + i * 3.0
                                draw_line(Vector2(-8, y_off), Vector2(-20, y_off - 4),
                                        Color(0.78, 0.78, 0.78), 1.5)
                                draw_line(Vector2(8, y_off), Vector2(20, y_off - 4),
                                        Color(0.78, 0.78, 0.78), 1.5)
                EnemyType.SLIME:
                        # Blob gelatinoso: highlights
                        draw_circle(Vector2(-5, 2), 1.5, Color(0.78, 0.95, 0.78))
                        draw_circle(Vector2(5, 2), 1.5, Color(0.78, 0.95, 0.78))
                EnemyType.DEMON:
                        # Corna + ali
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -16), Vector2(-12, -26), Vector2(-4, -18),
                        ]), Color(0.31, 0.0, 0.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -16), Vector2(12, -26), Vector2(4, -18),
                        ]), Color(0.31, 0.0, 0.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-12, -4), Vector2(-24, -8),
                                Vector2(-20, 8), Vector2(-8, 6),
                        ]), Color(0.47, 0.0, 0.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(12, -4), Vector2(24, -8),
                                Vector2(20, 8), Vector2(8, 6),
                        ]), Color(0.47, 0.0, 0.0))
                EnemyType.ROBOT:
                        # Antenna + LED + cingoli
                        draw_rect(Rect2(-1, -28, 2, 8), Color(0.31, 0.31, 0.31))
                        draw_circle(Vector2(0, -29), 2, Color(1.0, 0.2, 0.2))
                        draw_rect(Rect2(-14, 12, 28, 6), Color(0.12, 0.12, 0.12))
                EnemyType.GOBLIN:
                        # Orecchie appuntite + pugnale
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -10), Vector2(-16, -8), Vector2(-8, -6),
                        ]), Color(0.27, 0.71, 0.27))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -10), Vector2(16, -8), Vector2(8, -6),
                        ]), Color(0.27, 0.71, 0.27))
                        draw_rect(Rect2(8, -2, 2, 8), Color(0.78, 0.78, 0.78))
                EnemyType.ORC:
                        # Armatura + zanne
                        draw_rect(Rect2(-8, -6, 16, 8), Color(0.39, 0.39, 0.39))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-6, -12), Vector2(-8, -6), Vector2(-2, -10),
                        ]), Color(1.0, 1.0, 0.78))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(6, -12), Vector2(8, -6), Vector2(2, -10),
                        ]), Color(1.0, 1.0, 0.78))
                EnemyType.WRAITH:
                        # Mantello fluttuante + cappuccio
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -16), Vector2(14, -4),
                                Vector2(12, 14), Vector2(-12, 14),
                                Vector2(-14, -4),
                        ]), Color(0.16, 0.0, 0.24, 0.78))
                        draw_circle(Vector2(0, -16), 8, Color(0.08, 0.0, 0.12))
                EnemyType.GHOUL:
                        # Corpo decomposto: artigli
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-12, -2), Vector2(-18, 2), Vector2(-12, 4),
                        ]), Color(0.78, 0.78, 0.78))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(12, -2), Vector2(18, 2), Vector2(12, 4),
                        ]), Color(0.78, 0.78, 0.78))
                EnemyType.IMP:
                        # Piccolo con ali + corna
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -4), Vector2(-16, -12),
                                Vector2(-12, -2), Vector2(-2, 2),
                        ]), Color(0.47, 0.0, 0.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(2, -4), Vector2(16, -12),
                                Vector2(12, -2), Vector2(2, 2),
                        ]), Color(0.47, 0.0, 0.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-4, -16), Vector2(-8, -22), Vector2(-2, -16),
                        ]), Color(0.08, 0.08, 0.08))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(4, -16), Vector2(8, -22), Vector2(2, -16),
                        ]), Color(0.08, 0.08, 0.08))
                EnemyType.RAT:
                        # Coda lunga + muso
                        draw_line(Vector2(-12, 4), Vector2(-20, 8),
                                Color(1.0, 0.78, 0.78), 2)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -4), Vector2(18, -4), Vector2(12, 4),
                        ]), Color(0.39, 0.35, 0.31))
                EnemyType.CULTIST:
                        # Tunica con cappuccio + pugnale
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -14), Vector2(12, -4),
                                Vector2(8, 14), Vector2(-8, 14),
                                Vector2(-12, -4),
                        ]), Color(0.31, 0.0, 0.31))
                        draw_rect(Rect2(8, 2, 2, 10), Color(0.78, 0.78, 0.78))
                EnemyType.MIMIC:
                        # Forziere con denti
                        draw_rect(Rect2(-14, -4, 28, 14), Color(0.43, 0.27, 0.12))
                        draw_rect(Rect2(-14, -10, 28, 6), Color(0.31, 0.20, 0.08))
                        for i in 5:
                                var tx: float = -12.0 + i * 6.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(tx, -4), Vector2(tx + 4, -4),
                                        Vector2(tx + 2, 2),
                                ]), Color(1.0, 1.0, 0.86))
                EnemyType.WOLF:
                        # Coda arruffata + orecchie
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-14, -2), Vector2(-22, -8),
                                Vector2(-20, 2), Vector2(-14, 2),
                        ]), Color(0.24, 0.24, 0.27))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -16), Vector2(-6, -22), Vector2(0, -18),
                        ]), Color(0.31, 0.31, 0.35))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -16), Vector2(12, -22), Vector2(6, -18),
                        ]), Color(0.31, 0.31, 0.35))
                EnemyType.WITCH:
                        # Cappello a punta + pozione
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-12, -22), Vector2(12, -22), Vector2(2, -38),
                        ]), Color(0.08, 0.08, 0.08))
                        draw_rect(Rect2(8, 2, 4, 8), Color(0.39, 1.0, 0.39, 0.78))
                EnemyType.BONE_GOLEM:
                        # Gabbia toracica + teschio grande
                        for i in 3:
                                draw_rect(Rect2(-14, -4.0 + i * 5.0, 28, 2),
                                        Color(0.47, 0.47, 0.39))
                        draw_rect(Rect2(-9, -28, 18, 14), Color(0.86, 0.86, 0.78))
                EnemyType.ASH_SERPENT:
                        # Serpente sinuoso + lingua biforcuta
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-16, 8), Vector2(-8, 2),
                                Vector2(-2, 8), Vector2(8, 2),
                                Vector2(14, 8), Vector2(-2, -2),
                        ]), Color(0.47, 0.43, 0.39))
                        draw_line(Vector2(14, -4), Vector2(20, -4),
                                Color(1.0, 0.31, 0.31), 1)
                EnemyType.DAMNED_KNIGHT:
                        # Armatura nera + crepa luminosa + spada
                        draw_rect(Rect2(-11, -8, 22, 20), Color(0.16, 0.16, 0.20))
                        draw_rect(Rect2(-11, -26, 16, 14), Color(0.12, 0.12, 0.16))
                        draw_rect(Rect2(-4, -4, 2, 8), Color(1.0, 0.47, 0.0))
                        draw_rect(Rect2(12, -12, 2, 18), Color(0.71, 0.71, 0.71))
                EnemyType.MAD_WIZARD:
                        # Cappello con stella + pergamene fluttuanti
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-10, -24), Vector2(10, -24), Vector2(4, -42),
                        ]), Color(0.16, 0.08, 0.24))
                        draw_circle(Vector2(2, -32), 2, Color(1.0, 1.0, 0.39))
                        draw_rect(Rect2(-18, -6, 6, 8), Color(0.86, 0.78, 0.55))
                        draw_rect(Rect2(12, -4, 6, 8), Color(0.86, 0.78, 0.55))
                EnemyType.DEMONIC_CROW:
                        # Ali nere + becco metallico
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -4), Vector2(-20, -12),
                                Vector2(-16, 4), Vector2(-2, 4),
                        ]), Color(0.08, 0.08, 0.12))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(2, -4), Vector2(20, -12),
                                Vector2(16, 4), Vector2(2, 4),
                        ]), Color(0.08, 0.08, 0.12))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -12), Vector2(14, -10), Vector2(8, -8),
                        ]), Color(0.71, 0.71, 0.78))
                EnemyType.TENTACLE:
                        # Tentacolo con ventose
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-4, 12), Vector2(-10, 4),
                                Vector2(-6, -8), Vector2(2, -12),
                                Vector2(8, -4), Vector2(6, 12),
                        ]), Color(0.39, 0.31, 0.47))
                        for i in 3:
                                draw_circle(Vector2(-6.0 + i * 4.0, -4.0 + i * 4.0),
                                        1.5, Color(0.71, 0.59, 0.78))
                EnemyType.GARGOYLE:
                        # Ali di pietra + corna
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-10, -6), Vector2(-20, -12),
                                Vector2(-22, -4), Vector2(-18, 2), Vector2(-12, -2),
                        ]), Color(0.27, 0.27, 0.30))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(10, -6), Vector2(20, -12),
                                Vector2(22, -4), Vector2(18, 2), Vector2(12, -2),
                        ]), Color(0.27, 0.27, 0.30))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -24), Vector2(-12, -30), Vector2(-6, -26),
                        ]), Color(0.31, 0.31, 0.33))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -24), Vector2(12, -30), Vector2(6, -26),
                        ]), Color(0.31, 0.31, 0.33))
                EnemyType.WELL_SPIRIT:
                        # Corpo acquoso + bolle
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -20), Vector2(12, -8),
                                Vector2(10, 10), Vector2(-10, 10), Vector2(-12, -8),
                        ]), Color(0.47, 0.78, 1.0, 0.5))
                        for i in 3:
                                draw_circle(Vector2(-8.0 + i * 6.0, 4),
                                        1.0 + (i % 2), Color(0.78, 0.94, 1.0, 0.71))
                EnemyType.CURSED_BOAR:
                        # Zanne + 4 zampe
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(10, -4), Vector2(16, -2), Vector2(10, 2),
                        ]), Color(0.78, 0.78, 0.71))
                        for i in 4:
                                draw_rect(Rect2(-12.0 + i * 8.0, 8, 4, 6),
                                        Color(0.24, 0.18, 0.14))
                EnemyType.PREDATOR_FUNGUS:
                        # Cappello fungo + macchie luminose
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-16, -2), Vector2(-12, -14),
                                Vector2(0, -18), Vector2(12, -14), Vector2(16, -2),
                        ]), Color(0.71, 0.31, 0.78))
                        for i in 3:
                                draw_circle(Vector2(-8.0 + i * 6.0, -12),
                                        1.5, Color(1.0, 0.86, 0.39))
                _:
                        pass

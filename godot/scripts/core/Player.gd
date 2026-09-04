# ===========================================================================
# Player.gd - Player character for Arcade Maze Fantasy (Godot port).
#
# Port of src/Player.h and src/Player.cpp (SFML/C++ -> GDScript).
#
# Movement: "grid-aligned" in the maze (snap-to-cell-centre before turning),
# but free pixel movement in the boss room (freeMovement=true).
#
# Lifecycle: lives (3) -> each life has maxEnergy (5) energy points.
# When energy reaches 0 a life is lost and the player respawns. The player is
# invulnerable for ~1 s after taking damage (damageTimer), or fully invincible
# while the chalice effect is active (invincibleTimer).
#
# Timers are stored in "simulated ms" (decremented by 16 per frame @ 60 FPS),
# exactly mirroring the C++ implementation so balance stays identical.
#
# Weapon system: pistol/shotgun/rocket/laser. Each shot consumes 1 ammo;
# with 0 ammo the player cannot shoot until they pick up a new weapon.
# ===========================================================================
class_name Player
extends CharacterBody2D

# --- Engine config ----------------------------------------------------------
# Run in physics step so timers/snap-to-grid stay deterministic at 60 FPS.
# Game node is expected to call `update_player()` from its own _physics_process;
# we don't tick ourselves here so the Game can pause us, slow-mo, etc.

# --- Grid constants (mirror Utils.h) ---------------------------------------
const WINDOW_WIDTH: int = 1024
const WINDOW_HEIGHT: int = 1024
const TILE_SIZE: int = 48
const MAZE_COLS: int = 21
const MAZE_ROWS: int = 19
const UI_HEIGHT: int = 80

# Cell-type values matching GameConstants.CellType enum (so this script works
# whether the caller passes our own Maze or the central GameConstants one):
#   EMPTY = 0, WALL = 1, TREASURE = 2, WEAPON = 3.
const CELL_EMPTY: int = 0
const CELL_WALL: int = 1
const CELL_TREASURE: int = 2
const CELL_WEAPON: int = 3

# --- Weapon types (mirror Weapon.h) -----------------------------------------
enum WeaponType { PISTOL, SHOTGUN, ROCKET, LASER }

# --- Playable characters (mirror Player.h CharacterType) --------------------
# 9 entries in C++ enum (HERO_M..VAMPIRE), though the C++ comment says 8 -
# the comment is a stale bug; we keep all 9.
enum CharacterType { HERO_M, HERO_F, MAGE, ORC, ELF, KNIGHT, GOLEM, DRAGON, VAMPIRE }

# Sprite base path per character (assets/sprites/<base>_sheet.png plus
# <base>_walk0..3_sheet.png and <base>_jump_sheet.png).
const CHARACTER_SPRITE_BASE := {
        CharacterType.HERO_M:   "res://assets/sprites/player1",
        CharacterType.HERO_F:   "res://assets/sprites/player2",
        CharacterType.MAGE:     "res://assets/sprites/char_mage",
        CharacterType.ORC:      "res://assets/sprites/char_orc",
        CharacterType.ELF:      "res://assets/sprites/char_elf",
        CharacterType.KNIGHT:   "res://assets/sprites/char_knight",
        CharacterType.GOLEM:    "res://assets/sprites/char_golem",
        CharacterType.DRAGON:   "res://assets/sprites/char_dragon",
        CharacterType.VAMPIRE:  "res://assets/sprites/char_vampire",
}

# Descriptive name shown in UI menus.
const CHARACTER_NAME := {
        CharacterType.HERO_M:   "HERO",
        CharacterType.HERO_F:   "HEROINE",
        CharacterType.MAGE:     "MAGE",
        CharacterType.ORC:      "ORC",
        CharacterType.ELF:      "ELF",
        CharacterType.KNIGHT:   "KNIGHT",
        CharacterType.GOLEM:    "GOLEM",
        CharacterType.DRAGON:   "DRAGON",
        CharacterType.VAMPIRE:   "VAMPIRE",
}

# Whether the sprite PNG default-facing is RIGHT (true) or LEFT (false).
# Drives flip logic: default-RIGHT -> flipped when lastDx < 0.
# Verified per-character via VLM/user-feedback in the original game.
const SPRITE_DEFAULT_FACES_RIGHT := {
        CharacterType.HERO_M:   true,
        CharacterType.HERO_F:   false,
        CharacterType.MAGE:     true,
        CharacterType.ORC:      false,
        CharacterType.ELF:      false,
        CharacterType.KNIGHT:   false,
        CharacterType.GOLEM:    false,
        CharacterType.DRAGON:   true,
        CharacterType.VAMPIRE:  true,
}

# --- Tunable stats ----------------------------------------------------------
@export var lives: int = 3
@export var max_energy: int = 5
@export var energy: int = 5
@export var score: int = 0
@export var speed: int = 2  # base speed (px/frame @ 60 FPS)

# --- Public state -----------------------------------------------------------
# Direction:
#   dx,dy          = current movement direction (applied this frame)
#   nextDx,nextDy  = direction requested by input (applied at next cell centre)
#   lastDx,lastDy  = last non-zero direction (orients sprite/weapon when idle)
var dx: int = 0
var dy: int = 0
var next_dx: int = 0
var next_dy: int = 0
var last_dx: int = 1
var last_dy: int = 0

# Weapon / projectiles
var current_weapon: Dictionary = {
        "type": WeaponType.PISTOL,
        "power": 1,
        "ammo": 15,
}
# Each projectile is a Dictionary {pos: Vector2, dir: Vector2, power: int,
# active: bool, type: WeaponType}. Erase-remove is done in update_player().
var projectiles: Array[Dictionary] = []

# Flag: true if the player picked up a weapon THIS frame.
# Game::update consumes it via consume_picked_weapon() to play the load SFX.
var picked_weapon_this_frame: bool = false

# --- Timers (simulated ms; -16 per frame @ 60 FPS, floored at 0) -----------
var jump_timer: int = 0       # >0 = airborne (immune to damage)
var max_jump_time: int = 40   # frames the jump lasts (Player.h:138)
var jump_offset: float = 0.0 # visual arc offset, computed via sin(progress*pi)*25
var damage_timer: int = 0    # post-hit invulnerability (~1 s)
var invincible_timer: int = 0  # chalice-of-immortality total invuln (ms)
var speed_boost_timer: int = 0 # temporary post-jump-over-enemy speed boost (ms)
var permanent_speed_boost: bool = false  # winged boots: persists until death
var shoot_cooldown: int = 0
var shoot_anim_timer: int = 0  # >0 = attack animation playing
var anim_time: int = 0  # accumulated for idle/walk anim (NEVER reset)
var next_life_threshold: int = 100000  # extra life every 100k points

# --- Character selection ----------------------------------------------------
var character_type: int = CharacterType.HERO_M
var player_num: int = 1
# tint modulates the sprite (white = no tint for P1, light blue for P2)
var tint: Color = Color.WHITE

# Sprite nodes (assigned by load_character_sprite or set in editor).
# Player sprite is 64x64 side-view; feet anchor at (32, 56) in C++,
# here we use the Sprite2D centered horizontally + offset down by 24.
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var weapon_sprite: Sprite2D = $WeaponSprite if has_node("WeaponSprite") else null
# Visual jump offset is applied to the sprite, not the Node2D position.
# We track the last applied flip so it persists when last_dx == 0.
var _last_flipped: bool = false


# ===========================================================================
# Lifecycle
# ===========================================================================
func _ready() -> void:
        # Starting stats: position (1,1) cell, 3 lives, full energy, pistol.
        reset()


# ===========================================================================
# reset(): full reset (new game / continue credit).
# Mirrors Player::reset() in src/Player.cpp line 99-108.
# ===========================================================================
func reset() -> void:
        reset_position()
        lives = 3
        max_energy = 5
        energy = max_energy
        score = 0
        next_life_threshold = 100000
        current_weapon = _make_weapon(WeaponType.PISTOL)
        projectiles.clear()
        picked_weapon_this_frame = false
        # Permanent boost is LOST on full reset (death). See Player.cpp:106.
        permanent_speed_boost = false
        invincible_timer = 0


# ===========================================================================
# reset_position(): respawn after losing 1 life / start of new level.
# Mirrors Player::resetPosition() in src/Player.cpp line 117-129.
#
# NOTE: this also clears `permanent_speed_boost` per user requirement -
# "no speed boost after death". The C++ source comment at line 126 is
# explicit: the winged-boots bonus does NOT survive death.
# ===========================================================================
func reset_position() -> void:
        # Start at centre of cell (1, 1) inside the maze area (below UI bar).
        position = Vector2(
                1 * TILE_SIZE + TILE_SIZE / 2.0,
                1 * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT
        )
        dx = 0
        dy = 0
        next_dx = 0
        next_dy = 0
        last_dx = 1
        last_dy = 0
        speed = 2
        jump_timer = 0
        max_jump_time = 0
        damage_timer = 0
        shoot_cooldown = 0
        shoot_anim_timer = 0
        anim_time = 0
        speed_boost_timer = 0
        permanent_speed_boost = false  # fix: no speed boost after death
        invincible_timer = 0
        jump_offset = 0.0


# ===========================================================================
# set_position(new_x, new_y): absolute pixel position (used in boss mode to
# place the player at the bottom of the boss room). Stops movement.
# Mirrors Player::setPosition() line 161-163.
# ===========================================================================
func set_position_abs(new_x: float, new_y: float) -> void:
        position = Vector2(new_x, new_y)
        dx = 0
        dy = 0
        next_dx = 0
        next_dy = 0


# ===========================================================================
# Character selection
# ===========================================================================

# set_character(ct, pNum): set character type + player number, then load
# the matching sprite. If player_num == 2, applies a light blue tint to
# distinguish P1 from P2 when they share the same character.
func set_character(ct: int, p_num: int) -> void:
        character_type = ct
        player_num = p_num
        tint = _get_player_tint(p_num)
        load_character_sprite()


# Load the sprite for the current character_type from
# assets/sprites/<base>_sheet.png. Missing files fall back to nothing
# (the Game node can decide to draw a procedural fallback).
func load_character_sprite() -> void:
        var base: String = CHARACTER_SPRITE_BASE.get(character_type, CHARACTER_SPRITE_BASE[CharacterType.HERO_M])
        var path := base + "_sheet.png"
        if ResourceLoader.exists(path) and sprite:
                var tex := load(path)
                if tex is Texture2D:
                        sprite.texture = tex
                        sprite.modulate = tint
                        sprite.flip_h = false  # flip is applied per-frame in _update_sprite


# ===========================================================================
# Movement
# ===========================================================================

# set_direction(t_dx, t_dy): request a new direction (applied when aligned
# to cell centre, or immediately in free-movement mode).
func set_direction(t_dx: int, t_dy: int) -> void:
        next_dx = t_dx
        next_dy = t_dy


# try_move(t_dx, t_dy, maze): attempt to set movement toward (t_dx, t_dy).
# Returns true if the adjacent cell is open. Also updates last_dx/last_dy
# (so sprite/weapon orient correctly when the player stops).
# Mirrors Player::tryMove() line 170-185.
func try_move(t_dx: int, t_dy: int, maze: Object) -> bool:
        var col := int(position.x / TILE_SIZE)
        var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
        if not maze.is_wall(col + t_dx, row + t_dy):
                dx = t_dx
                dy = t_dy
                last_dx = t_dx
                last_dy = t_dy
                return true
        # Direction blocked: still orient the sprite/weapon, then stop.
        # (Without this, the player could be permanently stuck against a wall
        # because dx/dy would carry over from the previous frame.)
        last_dx = t_dx
        last_dy = t_dy
        dx = 0
        dy = 0
        return false


# ===========================================================================
# update_player(maze, free_movement): per-frame update.
# Mirrors Player::update() in src/Player.cpp line 202-315.
#
#  1. Jump arc visual offset (sin curve, max 25 px).
#  2. Decrement all timers by 16 ms (60 FPS cadence).
#  3. Movement:
#     - free_movement=true  : pixel-free movement bounded to the screen.
#     - free_movement=false : snap-to-grid; aligns to cell centre before
#       turning, applies requested direction at centre, stops if wall ahead.
#       Player stops IMMEDIATELY when direction released (next_dx == next_dy
#       == 0).
#  4. Cell pickups (treasure / weapon).
#  5. Projectile advance (8 px/frame) + erase-remove inactive.
# ===========================================================================
func update_player(maze: Object, free_movement: bool) -> void:
        # 1) Jump visual offset: half sin curve (0 -> peak -> 0 over max_jump_time).
        if jump_timer > 0:
                jump_timer -= 1
                var progress: float = 1.0 - float(jump_timer) / float(max_jump_time)
                jump_offset = sin(progress * PI) * 25.0
        else:
                jump_offset = 0.0

        # 2) Tick all simulated-ms timers (threshold to 0 to avoid leftover 1..15).
        damage_timer = _tick_timer(damage_timer)
        shoot_cooldown = _tick_timer(shoot_cooldown)
        shoot_anim_timer = _tick_timer(shoot_anim_timer)
        anim_time += 16
        speed_boost_timer = _tick_timer(speed_boost_timer)
        tick_invincible_timer()

        # Effective speed: base 2, +1 if any boost active (permanent or temp).
        var boosted: bool = permanent_speed_boost or speed_boost_timer > 0
        var effective_speed: int = speed + 1 if boosted else speed

        if free_movement:
                # --- Boss-room mode: free pixel movement ---
                if next_dx != 0 or next_dy != 0:
                        dx = next_dx
                        dy = next_dy
                        last_dx = dx
                        last_dy = dy
                        next_dx = 0
                        next_dy = 0
                else:
                        # No input pressed -> stop immediately (fix: prevent drift).
                        dx = 0
                        dy = 0
                position.x += dx * effective_speed
                position.y += dy * effective_speed
                # Clamp to screen bounds (16 px margin so half the sprite stays visible).
                position.x = clamp(position.x, 16, WINDOW_WIDTH - 16)
                position.y = clamp(position.y, UI_HEIGHT + 16, WINDOW_HEIGHT - 16)
        else:
                # --- Maze mode: snap-to-grid ---
                # FIX (line 245-247): if no direction pressed, stop IMMEDIATELY.
                if next_dx == 0 and next_dy == 0:
                        dx = 0
                        dy = 0

                var col := int(position.x / TILE_SIZE)
                var row := int((position.y - UI_HEIGHT) / TILE_SIZE)
                var center_x: float = col * TILE_SIZE + TILE_SIZE / 2.0
                var center_y: float = row * TILE_SIZE + TILE_SIZE / 2.0 + UI_HEIGHT

                # FIX (line 261-268): if idle and a new direction is pressed, align
                # to the current cell centre BEFORE try_move so the wall check uses
                # the correct cell (otherwise the player could clip through walls).
                if dx == 0 and dy == 0 and (next_dx != 0 or next_dy != 0):
                        position.x = center_x
                        position.y = center_y
                        try_move(next_dx, next_dy, maze)
                        next_dx = 0
                        next_dy = 0

                # When close enough to the cell centre, snap and try to turn.
                if absf(position.x - center_x) < effective_speed \
                                and absf(position.y - center_y) < effective_speed:
                        position.x = center_x
                        position.y = center_y
                        if next_dx != 0 or next_dy != 0:
                                try_move(next_dx, next_dy, maze)
                                next_dx = 0
                                next_dy = 0
                        # FIX (line 278-281): if a wall is now ahead, stop.
                        if dx != 0 or dy != 0:
                                if maze.is_wall(col + dx, row + dy):
                                        dx = 0
                                        dy = 0
                position.x += dx * effective_speed
                position.y += dy * effective_speed

                # Cell pickups: treasure (10000 pts + sparkle particles) or weapon.
                var cell_type: int = maze.get_cell_type(col, row)
                if cell_type == CELL_TREASURE:
                        maze.collect_treasure(col, row)
                        add_score(10000)
                        # Particle emission is left to the Game node (it owns particles).
                elif cell_type == CELL_WEAPON:
                        var w: Dictionary = maze.collect_weapon(col, row)
                        collect_weapon(w)
                        picked_weapon_this_frame = true

        # 5) Projectile advance: 8 px/frame, killed by walls (maze mode) or
        # out-of-bounds (always).
        var alive: Array[Dictionary] = []
        for p in projectiles:
                if not p.active:
                        continue
                if not free_movement:
                        var p_col := int(p.pos.x / TILE_SIZE)
                        var p_row := int((p.pos.y - UI_HEIGHT) / TILE_SIZE)
                        if maze.is_wall(p_col, p_row):
                                p.active = false
                                continue
                p.pos.x += p.dir.x * 8.0
                p.pos.y += p.dir.y * 8.0
                if p.pos.x < 0 or p.pos.x > WINDOW_WIDTH \
                                or p.pos.y < UI_HEIGHT or p.pos.y > WINDOW_HEIGHT:
                        p.active = false
                        continue
                alive.append(p)
        projectiles = alive

        # Apply sprite flip + jump offset for rendering.
        _update_sprite()


# ===========================================================================
# Shooting
# ===========================================================================

# shoot(): fire one projectile in the current direction. If idle, uses the
# last non-zero direction; if even that is zero (corner case), fires right.
# Consumes 1 ammo and triggers a short attack animation.
# Mirrors Player::shoot() line 323-354.
func shoot() -> void:
        if current_weapon.ammo <= 0:
                return

        var shoot_dx: int = dx if dx != 0 else last_dx
        var shoot_dy: int = dy if dy != 0 else last_dy
        if shoot_dx == 0 and shoot_dy == 0:
                shoot_dx = 1  # fallback: fire right

        # Spawn position: muzzle end of the weapon (gun barrel).
        # Horizontal shots fire from +20 px on the axis; vertical shots from
        # a slightly offset position (weapon held to the right of the body).
        var shoot_pos: Vector2
        if shoot_dx != 0:
                shoot_pos = Vector2(position.x + float(shoot_dx) * 20.0,
                                            position.y - 12.0)
        else:
                shoot_pos = Vector2(position.x + 4.0,
                                            position.y - 12.0 + float(shoot_dy) * 16.0)

        projectiles.append({
                "pos": shoot_pos,
                "dir": Vector2(float(shoot_dx), float(shoot_dy)),
                "power": current_weapon.power,
                "active": true,
                "type": current_weapon.type,
        })
        current_weapon.ammo -= 1
        # Trigger attack animation for ~300 ms (6 frames at 50 ms).
        shoot_anim_timer = 300


# ===========================================================================
# Damage / lives
# ===========================================================================

# take_damage(): applies 1 point of energy damage if NOT invulnerable and
# NOT jumping. On 0 energy, lose a life, restore energy, and respawn.
# Mirrors Player::takeDamage() line 364-374.
func take_damage() -> void:
        if is_jumping() or is_invulnerable():
                return
        energy -= 1
        damage_timer = 1000  # ~1 s of invulnerability after hit
        if energy <= 0:
                lives -= 1
                energy = max_energy
                reset_position()  # respawn


# collect_weapon(w): replace the current weapon (old one discarded).
# `w` is expected to be a Dictionary {type: WeaponType, power: int, ammo: int}.
func collect_weapon(w: Dictionary) -> void:
        current_weapon = w.duplicate()


# add_score(points): add points and grant an extra life every 100k.
func add_score(points: int) -> void:
        score += points
        if score >= next_life_threshold:
                lives += 1
                next_life_threshold += 100000


# add_life(): bonus life (reward after defeating a boss).
func add_life() -> void:
        lives += 1


# ===========================================================================
# Jump
# ===========================================================================

# activate_jump(): start a jump if not already jumping.
# Mirrors Player::activateJump() line 138.
func activate_jump() -> void:
        if jump_timer == 0:
                max_jump_time = 40
                jump_timer = max_jump_time


func is_jumping() -> bool:
        return jump_timer > 0


# ===========================================================================
# Invulnerability / Chalice
# ===========================================================================

# is_invulnerable(): true if either post-hit invuln OR chalice invincibility
# is active. Mirrors Player::isInvulnerable() line 133.
func is_invulnerable() -> bool:
        return damage_timer > 0 or invincible_timer > 0


# set_invincible_timer(ms): total invulnerability duration from the
# Golden Chalice. While > 0 the player takes no damage from anything and
# enemies they touch start burning.
func set_invincible_timer(ms: int) -> void:
        invincible_timer = ms


# tick_invincible_timer(): called every frame from update_player().
# Decrements by ~16 ms (matching 60 FPS frame step).
func tick_invincible_timer() -> void:
        invincible_timer = _tick_timer(invincible_timer)


# ===========================================================================
# Speed boosts
# ===========================================================================

# set_jump_speed_boost(ms): temporary speed boost after jumping over an
# enemy (sliding-forward effect). Lasts ~1000 ms by default.
func set_jump_speed_boost(ms: int) -> void:
        speed_boost_timer = ms


# activate_speed_boost(): permanent speed boost from winged boots.
# Survives reset_position() but is cleared by reset() (full death).
# Mirrors Player::activateSpeedBoost() line 198.
func activate_speed_boost() -> void:
        permanent_speed_boost = true


# has_speed_boost(): true if EITHER the permanent or temporary boost is on.
func has_speed_boost() -> bool:
        return permanent_speed_boost or speed_boost_timer > 0


# ===========================================================================
# get_grid_pos / get_pixel_pos
# ===========================================================================

# Grid position (col, row) computed from current pixel position.
# Used by Enemy AI to target the player.
func get_grid_pos() -> Vector2i:
        return Vector2i(
                int(position.x / TILE_SIZE),
                int((position.y - UI_HEIGHT) / TILE_SIZE)
        )

func get_pixel_pos() -> Vector2:
        return position


# ===========================================================================
# Helpers
# ===========================================================================

# _tick_timer(): decrement a simulated-ms timer by 16, floored at 0.
# Matches the `if (t > 16) t -= 16; else t = 0;` idiom in Player.cpp.
static func _tick_timer(t: int) -> int:
        return t - 16 if t > 16 else 0


# _make_weapon(t): factory mirroring Weapon::generate() in src/Weapon.cpp.
# Returns a Dictionary {type, power, ammo} matching the C++ struct Weapon.
static func _make_weapon(t: int) -> Dictionary:
        var power: int = 1
        var ammo: int = 15
        match t:
                WeaponType.PISTOL:
                        power = 1
                        ammo = 15
                WeaponType.SHOTGUN:
                        power = 3
                        ammo = 8
                WeaponType.LASER:
                        power = 2
                        ammo = 20
                WeaponType.ROCKET:
                        power = 5
                        ammo = 4
        return {"type": t, "power": power, "ammo": ammo}


# _get_player_tint(p_num): P1 = no tint (white), P2 = light blue.
# Mirrors getPlayerTint() line 59-66.
static func _get_player_tint(p_num: int) -> Color:
        if p_num == 2:
                return Color(0.784, 0.784, 1.0)  # (200, 200, 255)
        return Color.WHITE


# consume_picked_weapon(): one-shot flag for the Game to detect "weapon
# picked up this frame" and play the load SFX. Resets after consumption.
func consume_picked_weapon() -> bool:
        var v := picked_weapon_this_frame
        picked_weapon_this_frame = false
        return v


# ===========================================================================
# Sprite / flip handling
# ===========================================================================

# _update_sprite(): applies the side-view flip + jump offset each frame.
# Sprite is right-facing by default for HERO_M/MAGE/DRAGON/VAMPIRE; the
# others default left and the flip logic inverts.
#
# Behaviour (mirrors Player::render() line 432-443):
#   * last_dx > 0 -> no flip
#   * last_dx < 0 -> flip horizontally
#   * last_dx == 0 (idle / vertical movement) -> keep previous orientation
# The flip state persists across frames so a player who stops after moving
# left keeps facing left.
func _update_sprite() -> void:
        if sprite == null:
                return

        var default_right: bool = SPRITE_DEFAULT_FACES_RIGHT.get(
                character_type, true)

        # Determine desired flipped state (in world terms: "facing left").
        if last_dx > 0:
                _last_flipped = false
        elif last_dx < 0:
                _last_flipped = true
        # else: keep _last_flipped from previous frame.

        # If the sprite PNG defaults to LEFT, invert the flip so the visible
        # orientation still matches movement direction.
        if default_right:
                sprite.flip_h = _last_flipped
        else:
                sprite.flip_h = not _last_flipped

        # Apply jump arc as a vertical offset (sprite only, not the Node2D).
        # In C++ the sprite is drawn at pos.y + 24 - jumpOffset; here we shift
        # the sprite by -jumpOffset relative to its anchor.
        sprite.offset = Vector2(0, -jump_offset)

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
        # Load fire-aura spritesheet via SpriteManager (mirror C++ static
        # SpriteSheet load in Game::drawFireAura 3789-3794).
        if SpriteManager:
                _fire_aura_sheet = SpriteManager.get_sheet("effect_fireaura")
        # FIX (pallina gialla intermittente sotto il player): il PointLight2D
        # AuraLight creato qui era una luce gialla che pulsava sotto il player
        # e copriva quasi tutto lo sprite. L'utente lo ha segnalato come bug.
        # Rimuoviamo il PointLight2D — l'aura del player viene disegnata
        # proceduralmente solo quando è invincibile (chalice effect, vedi
        # _draw_fire_aura) e non come luce ambientale permanente.
        # FIX: la Camera2D viene ora creata da MainGameController._setup_camera
        # e aggiunta al Window root (NON come figlia del MainGame scalato né
        # del player). Questo evita che la camera erediti trasformazioni di
        # scale/position dai genitori. Player.gd non crea più la sua camera;
        # si limita a registrare la posizione del player per eventuali
        # screen-shake futuri (gestiti da EffectsManager.set_camera).
        # Non facciamo nulla qui — MainGameController._setup_camera() crea
        # una camera globale con zoom 1080/1024 = 1.0547 centrata su (512,512).


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
# assets/sprites/<base>_sheet.png. The main sheet is 256x64 (4 frames of 64x64).
# FIX (graphics gap #1 — per-frame walk/jump sheets were unused dead assets):
# The C++ engine (Player.cpp:132-139) loaded SIX sheets per character:
#   <base>_sheet.png, <base>_walk0..3_sheet.png, <base>_jump_sheet.png.
# Each sheet is a single 64x64 frame; the engine picked the right sheet per
# animation state (idle/walk0..3/jump). The previous Godot port only loaded
# the main sheet and used the 4 frames inside it as a walk cycle (frame 3
# doubling as the jump pose). The 48 dedicated walk/jump PNGs were dead weight.
# We now load all 6 sheets and pick the right one per state, recovering the
# per-frame art the asset pipeline already ships.
func load_character_sprite() -> void:
        var base: String = CHARACTER_SPRITE_BASE.get(character_type, CHARACTER_SPRITE_BASE[CharacterType.HERO_M])
        var path := base + "_sheet.png"
        if ResourceLoader.exists(path) and sprite:
                var tex := load(path)
                if tex is Texture2D:
                        # Store the full sheet; _update_sprite() will set the
                        # AtlasTexture for the current frame each frame.
                        _character_sheet_texture = tex
                        _character_sheet_path = base
                        sprite.modulate = tint
                        sprite.flip_h = false
                        # Pre-load the dedicated per-frame sheets. Each is a
                        # 64x64 single-frame PNG. Missing files are silently
                        # skipped — we fall back to the main sheet frames.
                        _walk_sheet_textures.resize(4)
                        for i in 4:
                                var walk_path := base + "_walk%d_sheet.png" % i
                                if ResourceLoader.exists(walk_path):
                                        var walk_tex := load(walk_path)
                                        if walk_tex is Texture2D:
                                                _walk_sheet_textures[i] = walk_tex
                                else:
                                        _walk_sheet_textures[i] = null
                        var jump_path := base + "_jump_sheet.png"
                        if ResourceLoader.exists(jump_path):
                                var jump_tex := load(jump_path)
                                if jump_tex is Texture2D:
                                        _jump_sheet_texture = jump_tex
                                else:
                                        _jump_sheet_texture = null
                        else:
                                _jump_sheet_texture = null
                        # Initial frame (idle = main sheet frame 0)
                        _apply_character_frame(0)
                        sprite_loaded = true
                        # FIX (sprite troppo piccoli): scale aumentata da 1.0 a 1.3
                        # per rendere il player più visibile nel tile 48px.
                        # 64*1.3=83px, leggermente più del tile ma visibile.
                        if sprite:
                                sprite.scale = Vector2(1.3, 1.3)
                                sprite.centered = true
                        # Apply CharacterArt enhancement shader (Godot-native sprite enhancement)
                        if CharacterArt and sprite:
                                CharacterArt.apply_enhancement(sprite, false)
                else:
                        sprite_loaded = false
        else:
                sprite_loaded = false


# Apply a specific frame index from the character sheet to the Sprite2D.
# The main sheet is 256x64 = 4 frames of 64x64.
# When a dedicated per-frame sheet exists for the requested state (walk/jump),
# we use it directly (it's already a 64x64 single-frame texture).
func _apply_character_frame(frame_idx: int) -> void:
        if _character_sheet_texture == null or sprite == null:
                return
        var fw: int = 64
        var fh: int = 64
        var cols: int = 4
        var idx: int = clampi(frame_idx, 0, cols - 1)
        var at := AtlasTexture.new()
        at.atlas = _character_sheet_texture
        at.region = Rect2(idx * fw, 0, fw, fh)
        sprite.texture = at


# Apply a dedicated single-frame texture (walk0..3 or jump) directly to the
# Sprite2D. Used by _update_sprite() when the dedicated sheet exists.
func _apply_character_dedicated_texture(tex: Texture2D) -> void:
        if tex == null or sprite == null:
                return
        sprite.texture = tex


var _character_sheet_texture: Texture2D = null
var _character_sheet_path: String = ""
var sprite_loaded: bool = false
# Dedicated per-frame sheets (loaded once at character-switch time).
# walk0..3 = walk cycle; jump = jump pose. Each is a single 64x64 frame.
# Any entry that's null means the dedicated sheet wasn't found on disk; we
# fall back to the main 4-frame sheet (_apply_character_frame).
var _walk_sheet_textures: Array = [null, null, null, null]
var _jump_sheet_texture: Texture2D = null

# Fire-aura spritesheet (effect_fireaura, 6x4 frames of 64x64, anchor 32,32).
# Loaded via SpriteManager in _ready() and used in _draw() while the chalice
# invincibility is active. Mirrors C++ Game::drawFireAura (3770-3879) which
# loads the same spritesheet as a static SpriteSheet instance.
var _fire_aura_sheet: Variant = null
var _fire_aura_anim_time: float = 0.0  # accumulates for the fire flicker


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
        # Trigger redraw so projectiles/aura/muzzle flash update visually.
        queue_redraw()


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
        # Effetti Godot-native: screen shake + particelle danno
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.25)
                var p := EffectsManager.spawn_sparks(get_pixel_pos(), 10)
                if get_parent():
                        get_parent().add_child(p)
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

        # FIX (player donna si gira dal lato opposto): la logica precedente
        # era confusa con l'inversione per default_left. Logica corretta:
        #   * Lo sprite PNG ha un facing di default (right o left).
        #   * flip_h = true specchia orizzontalmente lo sprite.
        #   * Vogliamo che il player guardi verso last_dx:
        #     - se last_dx > 0 (muove a destra), l'output deve guardare a destra
        #     - se last_dx < 0 (muove a sinistra), l'output deve guardare a sinistra
        #   * Se default_right: l'output "guarda destra" quando flip_h=false,
        #     "guarda sinistra" quando flip_h=true. Quindi:
        #       flip_h = (last_dx < 0)
        #   * Se default_left (NOT default_right): l'output "guarda sinistra"
        #     quando flip_h=false, "guarda destra" quando flip_h=true. Quindi:
        #       flip_h = (last_dx > 0)
        # In entrambi i casi, quando last_dx == 0 mantieni l'ultima orientazione.
        if last_dx > 0:
                # Moving right
                _last_flipped = false if default_right else true
        elif last_dx < 0:
                # Moving left
                _last_flipped = true if default_right else false
        # else: keep _last_flipped from previous frame.

        sprite.flip_h = _last_flipped

        # --- Animation frame selection ---
        # FIX (player cambia aspetto quando cammina/salta):
        # Le walk_sheet dedicate (player1_walk0..3_sheet.png) e il jump_sheet
        # dedicato hanno STILE DIVERSO dal main sheet (sono AI calls separate
        # con prompt diversi) → swap di texture cambiava aspetto/colore.
        # Il C++ (Player.cpp:432-443) NON swappava sheet per walk/jump:
        # usava il main 4-frame sheet per tutto, e applicava un arc Y
        # sinusoidale per il salto (lo stesso sprite che si alzava in aria).
        # Ora torniamo a quel modello: main sheet 4-frame per idle/walk/attack,
        # jump = stessa sprite con offset Y sin(progress*PI)*25 (effetto "salto
        # visivo" tipo arc, NON swap di texture).
        if is_jumping():
                # Jump: NON swappare texture. Usa frame 0 (idle) dello stesso
                # main sheet. L'offset Y (jump_offset) viene applicato sotto
                # per dare l'effetto "salto in aria" con il solito sprite.
                _apply_character_frame(0)
        elif shoot_anim_timer > 0:
                # Attack: use frame 3 (arm-up pose on main sheet) which reads
                # as an attack recoil. Same texture as walk/idle → no swap.
                _apply_character_frame(3)
        elif dx != 0 or dy != 0:
                # Walking: cycle frames 0-3 of the MAIN sheet at ~12 FPS
                # (FIX: era 130ms/frame = ~7.5fps, troppo lento → sembrava
                # statico. Ridotto a 80ms/frame = ~12.5fps, più visibile).
                var walk_frame: int = int(anim_time / 80.0) % 4
                _apply_character_frame(walk_frame)
        else:
                # Idle: frame 0 of the main sheet.
                _apply_character_frame(0)

        # Apply jump arc as a vertical offset (sprite only, not the Node2D).
        # In C++ the sprite is drawn at pos.y + 24 - jumpOffset; here we shift
        # the sprite by -jumpOffset relative to its anchor.
        sprite.offset = Vector2(0, -jump_offset)


# ===========================================================================
# _draw(): render projectiles fired by this player.
# Projectiles are stored in the `projectiles` Array[Dictionary].
# Each projectile dict has: pos, dir, power, active, type.
# ===========================================================================
func _draw() -> void:
        # Draw projectiles (relative to player node origin = player position)
        # 4 distinct shapes per weapon type (mirror C++ drawProjectiles)
        for proj in projectiles:
                if not proj.get("active", false):
                        continue
                var p_pos: Vector2 = proj.get("pos", Vector2.ZERO)
                # Convert world position to local (relative to player node)
                var local_pos: Vector2 = p_pos - position
                var w_type: int = proj.get("type", WeaponType.PISTOL)
                var col: Color = _projectile_color(w_type)
                match w_type:
                        WeaponType.LASER:
                                # Laser: thin elongated beam (14x3) rotated by direction
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                # Draw as elongated beam with circles along direction
                                for i in 7:
                                        var offset: Vector2 = dir * (i - 3) * 2
                                        draw_circle(local_pos + offset, 1.0, col)
                        WeaponType.SHOTGUN:
                                # Shotgun: 3 small pellets perpendicular to direction
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                var perp: Vector2 = Vector2(-dir.y, dir.x)
                                draw_circle(local_pos + perp * 2, 1.5, col)
                                draw_circle(local_pos, 2.0, col)
                                draw_circle(local_pos - perp * 2, 1.5, col)
                        WeaponType.ROCKET:
                                # Rocket: body + tip + trail
                                var dir: Vector2 = proj.get("dir", Vector2(1, 0))
                                # Trail
                                draw_circle(local_pos - dir * 6, 2.0, Color(1, 0.4, 0.1, 0.5))
                                draw_circle(local_pos - dir * 9, 1.5, Color(1, 0.3, 0.1, 0.3))
                                # Body
                                draw_circle(local_pos, 3.5, col)
                                draw_circle(local_pos, 2.5, Color(0.6, 0.3, 0.1))
                                # Tip
                                draw_circle(local_pos + dir * 3, 2.0, Color(1, 0.9, 0.4))
                        _:
                                # Pistol: small red fire bullet (was: huge yellow ball).
                                # FIX (pallino giallo troppo grande e giallo):
                                # era draw_circle(local_pos, 5.0, yellow) → ora 2px rosso.
                                draw_circle(local_pos, 2.0, col)
                                draw_circle(local_pos, 1.0, Color(1.0, 1.0, 0.8, 1.0))

        # Draw muzzle flash if shoot animation is playing.
        # FIX (muzzle flash troppo grande e giallo): era 8px+5px giallo,
        # ora 3px+2px rosso/arancio (più realistico).
        if shoot_anim_timer > 0:
                var flash_dir: Vector2 = Vector2(last_dx, last_dy)
                if flash_dir == Vector2.ZERO:
                        flash_dir = Vector2(1, 0)
                var flash_pos: Vector2 = flash_dir * 18.0
                draw_circle(flash_pos, 3.0, Color(1.0, 0.3, 0.1, 0.9))
                draw_circle(flash_pos, 1.5, Color(1.0, 0.9, 0.5, 1.0))

        # Draw invincibility aura (chalice effect) - detailed fire aura:
        # spritesheet + 3 glow circles + 12 procedural flames + 8 sparks +
        # central nucleus. Mirrors C++ Game::drawFireAura (3770-3879).
        if invincible_timer > 0:
                _draw_fire_aura()

        # Draw shadow (always visible, like C++)
        var shadow_y: float = 20.0 - jump_offset * 0.3
        draw_circle(Vector2(0, shadow_y), 12.0, Color(0, 0, 0, 0.3))

        # Fallback procedural character if no sprite loaded
        _draw_character_fallback()

        # Equipped weapon (drawn on top of body so it's visible when held).
        # Mirrors C++ Weapon::renderEquipped() in src/Weapon.cpp line 523-817.
        _draw_equipped_weapon()


func _projectile_color(w_type: int) -> Color:
        match w_type:
                WeaponType.PISTOL:
                        return Color(1.0, 0.25, 0.1)  # red fire (was yellow)
                WeaponType.SHOTGUN:
                        return Color(1.0, 0.5, 0.2)  # orange
                WeaponType.ROCKET:
                        return Color(1.0, 0.3, 0.1)  # red
                WeaponType.LASER:
                        return Color(0.3, 1.0, 0.3)  # green
                _:
                        return Color(1.0, 1.0, 1.0)


# ===========================================================================
# _draw_fire_aura(): detailed chalice invincibility aura.
#
# Renders (in local space, centered on the player):
#   0. effect_fireaura spritesheet frame (idle, animated by anim_time)
#   1. Outer gold glow circle (32px pulsing)
#   2. Inner dark-red glow circle (22px pulsing)
#   3. Mid gold glow circle (14px pulsing)
#   4. 12 procedural flames (gold base + red tip) arranged around the player
#   5. 8 white sparks ascending upward (animated by anim_time)
#   6. Central white nucleus (8px pulsing)
#
# Mirrors Game::drawFireAura in src/Game.cpp lines 3770-3879.
# All drawing happens at Vector2.ZERO since this is the player's local origin.
# ===========================================================================
func _draw_fire_aura() -> void:
        var COL_GOLD: Color = Color(220.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0)
        var COL_RED_L: Color = Color(200.0 / 255.0, 80.0 / 255.0, 80.0 / 255.0)
        var COL_RED_D: Color = Color(160.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0)
        var COL_WHITE: Color = Color(240.0 / 255.0, 240.0 / 255.0, 240.0 / 255.0)
        var inv_pulse: float = sin(float(invincible_timer) * 0.01) * 0.2 + 1.0
        # Persist anim time across frames (mirror C++ static fireAnimTime)
        _fire_aura_anim_time += 0.08
        var fire_anim: float = _fire_aura_anim_time

        # --- 0. Spritesheet PNG aura di fuoco (effect_fireaura) ---
        # 6x4 frames of 64x64 with anchor (32, 32). Blend is alpha (normale)
        # but procedural glows below give extra luminosity.
        if _fire_aura_sheet != null and _fire_aura_sheet.is_loaded():
                var frame_count: int = _fire_aura_sheet.get_frame_count("idle")
                if frame_count <= 0:
                        frame_count = 6
                var frame_idx: int = int(fire_anim * 1000.0 / 80.0) % frame_count
                if frame_idx < 0:
                        frame_idx = 0
                var tex: AtlasTexture = _fire_aura_sheet.get_frame_texture("idle", frame_idx)
                if tex != null:
                        var sprite_scale: float = 1.4 * inv_pulse
                        var fw: float = float(tex.get_width()) * sprite_scale
                        var fh: float = float(tex.get_height()) * sprite_scale
                        # Anchor (32, 32) of 64x64 frame = centered on player
                        draw_texture_rect(tex,
                                Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)

        # --- 1. Bagliore arancione pulsante (gold 32px) ---
        var glow_r: float = 32.0 * inv_pulse
        draw_circle(Vector2.ZERO, glow_r,
                Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 70.0 / 255.0))
        # --- 2. Bagliore interno rosso (22px) ---
        var inner_r: float = 22.0 * inv_pulse
        draw_circle(Vector2.ZERO, inner_r,
                Color(COL_RED_D.r, COL_RED_D.g, COL_RED_D.b, 100.0 / 255.0))
        # --- 3. Glow centrale oro (14px) ---
        var mid_r: float = 14.0 * inv_pulse
        draw_circle(Vector2.ZERO, mid_r,
                Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 90.0 / 255.0))

        # --- 4. 12 fiamme procedurali (gold base + red tip) ---
        # Alternate gold base / red tip - matches Game.cpp 3832-3858.
        for i in 12:
                var angle: float = (float(i) / 12.0) * TAU
                var fx: float = cos(angle) * 20.0
                var fy: float = sin(angle) * 20.0
                var flame_h: float = 10.0 + sin(fire_anim + float(i) * 0.7) * 5.0 + 5.0
                var flame_w: float = 3.5
                # Tip is offset horizontally by a sin wave for flicker
                var tip_x: float = fx + sin(fire_anim * 2.0 + float(i)) * 3.0
                var tip_y: float = fy - flame_h
                # Base oro (triangolo)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(fx - flame_w, fy),
                        Vector2(fx + flame_w, fy),
                        Vector2(tip_x, tip_y),
                ]), Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 220.0 / 255.0))
                # Apice rosso (triangolo piu' piccolo sovrapposto)
                var tip_h: float = flame_h * 0.6
                draw_colored_polygon(PackedVector2Array([
                        Vector2(fx - flame_w * 0.6, fy - flame_h * 0.4),
                        Vector2(fx + flame_w * 0.6, fy - flame_h * 0.4),
                        Vector2(tip_x, fy - flame_h - tip_h * 0.3),
                ]), Color(COL_RED_L.r, COL_RED_L.g, COL_RED_L.b, 230.0 / 255.0))

        # --- 5. 8 scintille bianche ascending ---
        # Sparks rise upward and fade as they go higher.
        for i in 8:
                var spark_x: float = sin(fire_anim * 1.5 + float(i) * 1.2) * 14.0
                var spark_y: float = -10.0 - float(int(fire_anim * 20.0 + float(i) * 8.0) % 35)
                var spark_r: float = 1.2 + sin(fire_anim + float(i)) * 0.5
                var fade: int = int(fire_anim * 20.0 + float(i) * 8.0) % 35
                draw_circle(Vector2(spark_x, spark_y), spark_r,
                        Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                (220.0 - float(fade) * 6.0) / 255.0))

        # --- 6. Nucleo centrale bianco pulsante (8px) ---
        var core_r: float = 8.0 * inv_pulse
        draw_circle(Vector2.ZERO, core_r,
                Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 180.0 / 255.0))


# ===========================================================================
# renderCharacterFallback(): procedural rendering when no sprite PNG is loaded.
# Mirrors C++ Player::renderCharacterFallback() - draws a unique shape per
# character type using draw_circle, draw_rect, draw_colored_polygon.
# Each character has distinct features: HERO_M (hat), HERO_F (hair), MAGE
# (cone+robe), ORC (tusks+green), ELF (hood+ears), KNIGHT (helm+plume),
# GOLEM (cracks+glow), DRAGON (crest+wings+tail), VAMPIRE (cape+fangs).
# ===========================================================================
func _draw_character_fallback() -> void:
        if sprite_loaded and sprite != null and sprite.texture != null:
                return  # sprite exists, no fallback needed
        var body_col: Color = Color(0.7, 0.6, 0.5)
        var accent_col: Color = Color(0.9, 0.8, 0.7)
        match character_type:
                CharacterType.HERO_M:
                        body_col = Color(0.5, 0.4, 0.3)
                        accent_col = Color(0.3, 0.3, 0.4)  # blue tunic
                CharacterType.HERO_F:
                        body_col = Color(0.6, 0.45, 0.4)
                        accent_col = Color(0.8, 0.2, 0.2)  # red hair
                CharacterType.MAGE:
                        body_col = Color(0.3, 0.2, 0.5)
                        accent_col = Color(0.5, 0.4, 0.8)  # purple robe
                CharacterType.ORC:
                        body_col = Color(0.3, 0.5, 0.2)
                        accent_col = Color(0.2, 0.3, 0.1)  # dark green
                CharacterType.ELF:
                        body_col = Color(0.8, 0.7, 0.5)
                        accent_col = Color(0.5, 0.4, 0.2)  # brown hood
                CharacterType.KNIGHT:
                        body_col = Color(0.6, 0.6, 0.65)
                        accent_col = Color(0.4, 0.4, 0.45)  # steel
                CharacterType.GOLEM:
                        body_col = Color(0.5, 0.48, 0.45)
                        accent_col = Color(1.0, 0.6, 0.1)  # glow eyes
                CharacterType.DRAGON:
                        body_col = Color(0.7, 0.2, 0.1)
                        accent_col = Color(0.9, 0.4, 0.1)  # red scales
                CharacterType.VAMPIRE:
                        body_col = Color(0.15, 0.1, 0.15)
                        accent_col = Color(0.8, 0.8, 0.9)  # pale skin
        # Body (circle)
        draw_circle(Vector2(0, 4), 12, body_col)
        # Head (circle)
        draw_circle(Vector2(0, -8), 8, accent_col)
        # Character-specific details
        match character_type:
                CharacterType.HERO_M:
                        # Hat (brown triangle)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(0, -22)
                        ]), Color(0.4, 0.3, 0.15))
                        # Eyes
                        draw_circle(Vector2(-3, -8), 1.5, Color.WHITE)
                        draw_circle(Vector2(3, -8), 1.5, Color.WHITE)
                CharacterType.HERO_F:
                        # Hair (red flowing)
                        draw_rect(Rect2(-8, -14, 16, 4), Color(0.8, 0.2, 0.2))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -12), Vector2(-12, -4), Vector2(-8, 0)
                        ]), Color(0.7, 0.15, 0.15))
                CharacterType.MAGE:
                        # Pointed hat
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(2, -26)
                        ]), Color(0.2, 0.15, 0.4))
                        # Robe bottom (wider)
                        draw_rect(Rect2(-14, 8, 28, 8), accent_col)
                        # Staff
                        draw_rect(Rect2(10, -8, 2, 20), Color(0.4, 0.3, 0.1))
                        draw_circle(Vector2(11, -10), 3, Color(0.3, 0.8, 1.0))
                CharacterType.ORC:
                        # Tusks
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -4), Vector2(-4, 0), Vector2(-1, 0)
                        ]), Color(0.9, 0.9, 0.8))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(2, -4), Vector2(4, 0), Vector2(1, 0)
                        ]), Color(0.9, 0.9, 0.8))
                        # Ears
                        draw_circle(Vector2(-9, -8), 2, body_col)
                        draw_circle(Vector2(9, -8), 2, body_col)
                CharacterType.ELF:
                        # Pointed ears
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -10), Vector2(-12, -6), Vector2(-8, -4)
                        ]), accent_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -10), Vector2(12, -6), Vector2(8, -4)
                        ]), accent_col)
                        # Hood
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -14), Vector2(8, -14), Vector2(6, -8), Vector2(-6, -8)
                        ]), Color(0.4, 0.3, 0.15))
                CharacterType.KNIGHT:
                        # Helm
                        draw_rect(Rect2(-7, -16, 14, 8), accent_col)
                        # Plume
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-2, -16), Vector2(2, -16), Vector2(0, -22)
                        ]), Color(0.8, 0.2, 0.2))
                        # Visor slit
                        draw_rect(Rect2(-4, -12, 8, 1), Color(0, 0, 0))
                CharacterType.GOLEM:
                        # Cracks (lines)
                        draw_line(Vector2(-6, -4), Vector2(-2, 4), Color(0.2, 0.18, 0.15), 1)
                        draw_line(Vector2(4, -6), Vector2(6, 2), Color(0.2, 0.18, 0.15), 1)
                        # Glowing eyes
                        draw_circle(Vector2(-3, -8), 2, accent_col)
                        draw_circle(Vector2(3, -8), 2, accent_col)
                CharacterType.DRAGON:
                        # Wings
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-8, -4), Vector2(-16, -10), Vector2(-14, 0), Vector2(-8, 4)
                        ]), accent_col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(8, -4), Vector2(16, -10), Vector2(14, 0), Vector2(8, 4)
                        ]), accent_col)
                        # Horns
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-4, -14), Vector2(-6, -20), Vector2(-2, -16)
                        ]), Color(0.5, 0.2, 0.05))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(4, -14), Vector2(6, -20), Vector2(2, -16)
                        ]), Color(0.5, 0.2, 0.05))
                CharacterType.VAMPIRE:
                        # Cape (behind body)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-10, -6), Vector2(-14, 12), Vector2(14, 12), Vector2(10, -6)
                        ]), Color(0.05, 0.0, 0.05))
                        # Fangs
                        draw_rect(Rect2(-3, -4, 1, 3), Color.WHITE)
                        draw_rect(Rect2(2, -4, 1, 3), Color.WHITE)
        # Flip indicator (small arrow if facing left)
        if last_dx < 0:
                draw_colored_polygon(PackedVector2Array([
                        Vector2(-14, 0), Vector2(-18, -2), Vector2(-18, 2)
                ]), accent_col)


# ===========================================================================
# _draw_equipped_weapon(): draws the equipped weapon beside the player when
# ammo > 0, oriented by `last_dx` (right when >= 0, left when < 0).
# Mirrors C++ Weapon::renderEquipped() in src/Weapon.cpp line 523-817.
# Each of the 4 weapon types has unique multi-layer rendering:
#   * PISTOL:  2-layer grip + body + slide + gold insert + barrel + muzzle
#   * SHOTGUN: 2-layer stock + double barrel + reflection + pump + groove
#   * ROCKET:  2-layer tube + metal band + rocket body + conical tip + fin + scope
#   * LASER:   glow + body + body top + 3-layer core (out/mid/inner) + emitter + ring
# ===========================================================================
func _draw_equipped_weapon() -> void:
        if current_weapon.ammo <= 0:
                return
        var y: float = -8.0  # weapon height (above body centre, near the grip)
        var facing_right: bool = last_dx >= 0

        match current_weapon.type:
                WeaponType.PISTOL:
                        # Grip (2 layers: dark base + lighter mid)
                        draw_rect(Rect2(_wxr(-3.0, 6.0, facing_right), y + 1, 6, 11),
                                Color(0.20, 0.10, 0.05))
                        draw_rect(Rect2(_wxr(-2.5, 5.0, facing_right), y + 1, 5, 11),
                                Color(0.33, 0.20, 0.10))
                        # Metal body + slide + gold insert
                        draw_rect(Rect2(_wxr(-4.0, 13.0, facing_right), y - 7, 13, 9),
                                Color(0.27, 0.27, 0.31))
                        draw_rect(Rect2(_wxr(-4.0, 13.0, facing_right), y - 7, 13, 3),
                                Color(0.47, 0.47, 0.51))
                        draw_rect(Rect2(_wxr(-3.0, 2.0, facing_right), y - 6, 2, 3),
                                Color(0.71, 0.55, 0.24))
                        # Barrel + muzzle
                        draw_rect(Rect2(_wxr(8.0, 8.0, facing_right), y - 5, 8, 5),
                                Color(0.33, 0.33, 0.37))
                        draw_circle(Vector2(_wxc(14.5, facing_right), y - 3.5), 1.5,
                                Color(0.06, 0.06, 0.06))
                WeaponType.SHOTGUN:
                        # Wooden stock (2 layers: dark base + lighter top)
                        draw_rect(Rect2(_wxr(-7.0, 14.0, facing_right), y + 3, 14, 10),
                                Color(0.27, 0.16, 0.07))
                        draw_rect(Rect2(_wxr(-7.0, 14.0, facing_right), y + 3, 14, 5),
                                Color(0.51, 0.31, 0.14))
                        # Double barrel + reflection
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 6, 20, 4),
                                Color(0.22, 0.22, 0.24))
                        draw_rect(Rect2(_wxr(-6.0, 20.0, facing_right), y - 1, 20, 4),
                                Color(0.20, 0.20, 0.22))
                        draw_rect(Rect2(_wxr(-5.0, 18.0, facing_right), y - 5.5, 18, 1),
                                Color(0.71, 0.71, 0.75))
                        # Pump + groove
                        draw_rect(Rect2(_wxr(1.0, 8.0, facing_right), y + 4, 8, 5),
                                Color(0.55, 0.35, 0.18))
                        draw_rect(Rect2(_wxr(4.0, 0.8, facing_right), y + 4.5, 0.8, 4),
                                Color(0.24, 0.14, 0.06))
                WeaponType.ROCKET:
                        # Tube (2 layers) + metal band
                        draw_rect(Rect2(_wxr(-9.0, 18.0, facing_right), y - 4, 18, 9),
                                Color(0.24, 0.35, 0.20))
                        draw_rect(Rect2(_wxr(-9.0, 18.0, facing_right), y - 4, 18, 3),
                                Color(0.39, 0.55, 0.31))
                        draw_rect(Rect2(_wxr(-2.0, 1.5, facing_right), y - 4, 1.5, 9),
                                Color(0.71, 0.71, 0.71))
                        # Rocket body + conical tip + fin
                        draw_rect(Rect2(_wxr(5.0, 8.0, facing_right), y - 2.5, 8, 5),
                                Color(0.71, 0.20, 0.20))
                        _draw_wpoly(PackedVector2Array([
                                Vector2(13.0, y - 2.5),
                                Vector2(13.0, y + 2.5),
                                Vector2(17.0, y),
                        ]), Color(0.86, 0.31, 0.31), facing_right)
                        _draw_wpoly(PackedVector2Array([
                                Vector2(5.0, y - 2.5),
                                Vector2(8.0, y - 2.5),
                                Vector2(6.5, y - 5.0),
                        ]), Color(0.55, 0.12, 0.12), facing_right)
                        # Scope
                        draw_rect(Rect2(_wxr(-3.0, 6.0, facing_right), y - 7, 6, 2),
                                Color(0.12, 0.12, 0.16))
                WeaponType.LASER:
                        # Glow
                        draw_circle(Vector2(_wxc(-8.0, facing_right), y - 6), 8,
                                Color(0.31, 0.86, 1.0, 0.24))
                        # Body (2 layers: base + top)
                        draw_rect(Rect2(_wxr(-5.0, 16.0, facing_right), y - 4, 16, 9),
                                Color(0.20, 0.22, 0.31))
                        draw_rect(Rect2(_wxr(-5.0, 16.0, facing_right), y - 4, 16, 3),
                                Color(0.39, 0.43, 0.59))
                        # Luminous core (3 layers: outer / mid / inner)
                        draw_circle(Vector2(_wxc(-4.0, facing_right), y - 4), 4,
                                Color(0.39, 0.78, 1.0, 0.86))
                        draw_circle(Vector2(_wxc(-2.5, facing_right), y - 2.5), 2.5,
                                Color(0.71, 0.94, 1.0, 0.94))
                        draw_circle(Vector2(_wxc(-1.2, facing_right), y - 1.2), 1.2,
                                Color(1.0, 1.0, 1.0, 0.98))
                        # Emitter + luminous ring
                        draw_rect(Rect2(_wxr(8.0, 7.0, facing_right), y - 3, 7, 5),
                                Color(0.27, 0.31, 0.43))
                        draw_circle(Vector2(_wxc(13.0, facing_right), y - 2), 2,
                                Color(0.59, 1.0, 1.0, 0.86))


# _wxr(offset, width, facing_right): returns the X coordinate of a weapon
# rect's left edge, mirrored around the player centre when facing left.
# `offset` is the right-facing left-edge offset from x=0.
static func _wxr(offset: float, w: float, facing_right: bool) -> float:
        if facing_right:
                return offset
        return -offset - w


# _wxc(offset, facing_right): returns the X coordinate of a weapon circle
# centre, mirrored around the player centre when facing left.
static func _wxc(offset: float, facing_right: bool) -> float:
        return offset if facing_right else -offset


# _draw_wpoly(points, color, facing_right): draws a polygon for the equipped
# weapon, mirroring all X coordinates around the player centre when facing
# left.
func _draw_wpoly(points: PackedVector2Array, col: Color, facing_right: bool) -> void:
        if facing_right:
                draw_colored_polygon(points, col)
                return
        var mirrored := PackedVector2Array()
        mirrored.resize(points.size())
        for i in points.size():
                mirrored[i] = Vector2(-points[i].x, points[i].y)
        draw_colored_polygon(mirrored, col)

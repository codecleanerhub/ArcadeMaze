## Collectibles.gd - Maze items: mines, chalice, scepter, speed boots,
##                  treasures, exit door and magic portal.
## ============================================================
## Godot port of the items defined in `src/Game.h` (struct Mine,
## GoldenChalice, MagicScepter, SpeedBootsBonus, ExitDoor, MagicPortal)
## and the corresponding Cell.treasure / TreasureType from `src/Maze.h`.
##
## Each kind of item is a small Node2D with its own update/render logic.
## The Game scene instantiates them as needed and calls `update_step()`
## each frame; the player's collision logic queries `active` and `pos`.
extends Node2D
class_name Collectibles

# Treasure kinds (mirror C++ enum TreasureType).
enum TreasureType { TRES_CROWN, TRES_GOLD, TRES_CHEST, TRES_GEM, TRES_CUP }

# All treasure kinds (5) give the same score on collection.
const TREASURE_COUNT := 5
const TREASURE_POINTS := 10000

# Power-up types (sub-enum for the collectibles kinds themselves).
enum Kind {
        MINE,            # Explosive bouncing ball (1 per level, also in boss room).
        CHALICE,         # Golden chalice - 15s of player invincibility.
        SCEPTER,         # Lightning scepter - 5 strikes at 3s intervals.
        SPEED_BOOTS,     # Permanent speed boost (P1 or P2 owner).
        TREASURE,        # One of the 5 treasures (crown/gold/chest/gem/cup).
        EXIT_DOOR,       # Appears once all treasures are collected.
        MAGIC_PORTAL,    # Spawns at 50% enemies killed; respawns enemies.
}

@export var kind: int = Kind.TREASURE:
        set(v):
                kind = v
                _apply_kind_defaults()

@export var treasure_type: int = TreasureType.TRES_CROWN

@export var active: bool = true

# Position in pixels (top-left origin, +Y down).
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v

# Per-item animation state.
var anim_time: float = 0.0
var pulse: float = 0.0
var bob_offset: float = 0.0
var rotation_deg: float = 0.0

# --- MINE-specific ---
var bouncing: bool = false
var velocity: Vector2 = Vector2.ZERO
var bounce_timer_ms: int = 0
var in_boss_room: bool = false

# --- SCEPTER-specific ---
var triggered: bool = false
var lightnings_left: int = 0
var lightning_timer_ms: int = 0  # ms to next strike

# --- SPEED_BOOTS-specific ---
var owner_id: int = 0  # 0 = free (1P), 1 = P1, 2 = P2

# --- EXIT_DOOR-specific ---
var door_anim_timer_ms: int = 0
var door_glow_pulse: float = 0.0

# --- MAGIC_PORTAL-specific ---
var portal_phase: int = 0       # 0=open, 1=spawn, 2=close, 3=idle
var portal_phase_timer_ms: int = 0
var portal_enemies_to_spawn: int = 0
var portal_spawn_timer_ms: int = 0

# ----- Signals -----
# Emitted when an item is collected by the player. `player_id` is 1 or 2.
signal collected(item: Collectibles, player_id: int)
# Emitted when a scepter's lightning strike should fire.
signal lightning_strike(target_pos: Vector2)


func _ready() -> void:
        _apply_kind_defaults()


func _apply_kind_defaults() -> void:
        match kind:
                Kind.MINE:
                        rotation_deg = 0.0
                        pulse = 0.0
                        bouncing = false
                        bounce_timer_ms = 0
                Kind.CHALICE:
                        pulse = 0.0
                        bob_offset = 0.0
                Kind.SCEPTER:
                        pulse = 0.0
                        bob_offset = 0.0
                        lightnings_left = 5
                        lightning_timer_ms = 3000
                Kind.SPEED_BOOTS:
                        bob_offset = 0.0
                        owner_id = 0
                Kind.EXIT_DOOR:
                        door_anim_timer_ms = 0
                        door_glow_pulse = 0.0
                Kind.MAGIC_PORTAL:
                        portal_phase = 0
                        portal_phase_timer_ms = 0


# =========================================================
# Update step (delta_ms ≈ 16ms per frame at 60fps)
# =========================================================
# `player_pos` is the pixel position of the active player (P1) for collision
# detection. Set by the Game. For 2P, call twice (once per player).
func update_step(delta_ms: int, player_pos: Vector2, player_id: int = 1) -> void:
        if not active:
                return
        anim_time += float(delta_ms) * 0.001
        bob_offset = sin(anim_time * 3.0) * 2.0
        pulse = (sin(anim_time * 4.0) + 1.0) * 0.5
        rotation_deg += float(delta_ms) * 0.1
        match kind:
                Kind.MINE:
                        _update_mine(delta_ms)
                Kind.CHALICE:
                        pass  # only anim
                Kind.SCEPTER:
                        _update_scepter(delta_ms)
                Kind.SPEED_BOOTS:
                        pass
                Kind.TREASURE:
                        pass
                Kind.EXIT_DOOR:
                        _update_door(delta_ms)
                Kind.MAGIC_PORTAL:
                        _update_portal(delta_ms)

        # Collision: 16px radius for small items, 24px for the door/portal.
        var coll_radius := 16.0
        if kind == Kind.EXIT_DOOR or kind == Kind.MAGIC_PORTAL:
                coll_radius = 24.0
        elif kind == Kind.MINE:
                coll_radius = 12.0
        if active and pos.distance_to(player_pos) <= coll_radius:
                _on_collected(player_id)


# =========================================================
# Per-kind update helpers
# =========================================================

func _update_mine(delta_ms: int) -> void:
        if bouncing:
                # Bounce physics: gravity + floor bounce.
                velocity.y += 0.2  # gravity (px/frame²)
                pos += velocity
                rotation_deg += 6.0
                # Simple horizontal bounce off the room bounds.
                if pos.x < 64.0 or pos.x > 1024.0 - 64.0:
                        velocity.x = -velocity.x
                if bounce_timer_ms > delta_ms:
                        bounce_timer_ms -= delta_ms
                else:
                        bouncing = false
                        bounce_timer_ms = 0
                        active = false
                        collected.emit(self, 0)  # mine expired (no player)


func _update_scepter(delta_ms: int) -> void:
        if triggered:
                if lightning_timer_ms > delta_ms:
                        lightning_timer_ms -= delta_ms
                else:
                        if lightnings_left > 0:
                                # Fire a strike at a random target near the player position.
                                # The Game can override this target via the lightning_strike
                                # signal (e.g. to pick the closest enemy/boss).
                                lightnings_left -= 1
                                lightning_timer_ms = 3000
                                lightning_strike.emit(pos + Vector2(randf_range(-200, 200), randf_range(-200, 200)))
                        else:
                                active = false


func _update_door(delta_ms: int) -> void:
        if door_anim_timer_ms > 0:
                door_anim_timer_ms = maxi(0, door_anim_timer_ms - delta_ms)
        door_glow_pulse = (sin(anim_time * 3.0) + 1.0) * 0.5


func _update_portal(delta_ms: int) -> void:
        if portal_phase_timer_ms > delta_ms:
                portal_phase_timer_ms -= delta_ms
        else:
                match portal_phase:
                        0:  # opening
                                portal_phase = 1
                                portal_phase_timer_ms = 4000
                        1:  # spawning
                                if portal_enemies_to_spawn > 0:
                                        portal_enemies_to_spawn -= 1
                                        portal_spawn_timer_ms = 4000
                                        portal_phase_timer_ms = 4000
                                else:
                                        portal_phase = 2
                                        portal_phase_timer_ms = 1000
                        2:  # closing
                                portal_phase = 3
                                portal_phase_timer_ms = 0
                                active = false
                        3:
                                active = false
        if portal_phase == 1 and portal_enemies_to_spawn > 0:
                if portal_spawn_timer_ms > delta_ms:
                        portal_spawn_timer_ms -= delta_ms
                else:
                        portal_enemies_to_spawn -= 1
                        portal_spawn_timer_ms = 4000


# =========================================================
# Public API for the Game to configure items
# =========================================================

# --- MINE ---
func start_bounce(initial_vel: Vector2, duration_ms: int = 1500) -> void:
        bouncing = true
        velocity = initial_vel
        bounce_timer_ms = duration_ms

# --- CHALICE ---
func consume_chalice() -> int:
        # Returns the invincibility duration in ms (15 seconds).
        if kind == Kind.CHALICE and active:
                active = false
                return 15000
        return 0

# --- SCEPTER ---
func trigger_scepter() -> void:
        if kind == Kind.SCEPTER and active and not triggered:
                triggered = true
                lightnings_left = 5
                lightning_timer_ms = 0  # fire immediately on first frame

# --- SPEED BOOTS ---
func consume_boots(player_id: int) -> void:
        if kind == Kind.SPEED_BOOTS and active:
                active = false
                owner_id = player_id


# =========================================================
# Collision callback
# =========================================================
func _on_collected(player_id: int) -> void:
        match kind:
                Kind.MINE:
                        # Mine activates on touch: starts bouncing in a random direction
                        # at moderate speed. The Game's collision logic detects enemy
                        # hits during the bounce; after bounce_timer expires the mine
                        # deactivates.
                        if not bouncing:
                                var ang := randf() * TAU
                                start_bounce(Vector2(cos(ang), sin(ang)) * 4.0, 1500)
                Kind.CHALICE:
                        active = false
                        collected.emit(self, player_id)
                Kind.SCEPTER:
                        # Don't deactivate yet — scepter has 5 strikes to fire.
                        trigger_scepter()
                        collected.emit(self, player_id)
                Kind.SPEED_BOOTS:
                        consume_boots(player_id)
                        collected.emit(self, player_id)
                Kind.TREASURE:
                        active = false
                        collected.emit(self, player_id)
                Kind.EXIT_DOOR:
                        # Door activation is handled by Game (level transition).
                        collected.emit(self, player_id)
                Kind.MAGIC_PORTAL:
                        # Portal is not collectible.
                        pass


# =========================================================
# Rendering
# =========================================================
func _draw() -> void:
        if not active:
                if kind == Kind.EXIT_DOOR:
                        # Door stays visible briefly during its open animation.
                        if door_anim_timer_ms > 0:
                                _draw_exit_door()
                return
        match kind:
                Kind.MINE:         _draw_mine()
                Kind.CHALICE:      _draw_chalice()
                Kind.SCEPTER:      _draw_scepter()
                Kind.SPEED_BOOTS:  _draw_speed_boots()
                Kind.TREASURE:     _draw_treasure()
                Kind.EXIT_DOOR:    _draw_exit_door()
                Kind.MAGIC_PORTAL: _draw_magic_portal()


func _draw_mine() -> void:
        # Spiky ball: dark grey circle with 8 triangular spikes.
        var r := 10.0 + pulse * 1.5
        var col := Color(0.7, 0.6, 0.3)
        var dark := Color(0.2, 0.2, 0.2)
        draw_circle(Vector2.ZERO, r, col)
        # Spikes
        for i in range(8):
                var a := (float(i) / 8.0) * TAU + deg_to_rad(rotation_deg)
                var tip := Vector2(cos(a), sin(a)) * (r + 4.0)
                var base_l := Vector2(cos(a + 0.3), sin(a + 0.3)) * r
                var base_r := Vector2(cos(a - 0.3), sin(a - 0.3)) * r
                draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), dark)
        # Blinking red light
        if fmod(anim_time, 1.0) > 0.5:
                draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.2, 0.2))


func _draw_chalice() -> void:
        # Golden chalice with a pulsing aura.
        var aura_r := 18.0 + pulse * 3.0
        draw_circle(Vector2.ZERO - Vector2(0, bob_offset), aura_r,
                                Color(1.0, 0.85, 0.2, 0.20))
        # Cup body
        var gold := Color(1.0, 0.85, 0.2)
        var y_off := -bob_offset
        var top := Rect2(-8.0, -10.0 + y_off, 16.0, 4.0)
        var body := Rect2(-6.0, -6.0 + y_off, 12.0, 10.0)
        var base := Rect2(-3.0, 4.0 + y_off, 6.0, 4.0)
        draw_rect(top, gold)
        draw_rect(body, gold)
        draw_rect(base, gold)
        # Stem
        draw_rect(Rect2(-1.5, -2.0 + y_off, 3.0, 6.0), gold)
        # Highlight
        draw_rect(Rect2(-5.0, -5.0 + y_off, 2.0, 4.0), Color(1.0, 1.0, 0.7))


func _draw_scepter() -> void:
        # Tall staff with a glowing purple gem on top.
        var y_off := -bob_offset
        # Aura
        draw_circle(Vector2(0, -14 + y_off), 12.0 + pulse * 3.0,
                                Color(0.85, 0.2, 1.0, 0.25))
        # Staff
        draw_rect(Rect2(-1.5, -10 + y_off, 3.0, 22.0), Color(0.5, 0.35, 0.2))
        # Gem
        draw_circle(Vector2(0, -14 + y_off), 6.0, Color(0.85, 0.2, 1.0))
        draw_circle(Vector2(0, -14 + y_off), 3.0, Color(1.0, 0.9, 1.0))


func _draw_speed_boots() -> void:
        # Winged boot icon.
        var y_off := -bob_offset
        # Boot
        draw_rect(Rect2(-6.0, 0.0 + y_off, 10.0, 6.0), Color(0.4, 0.3, 0.2))
        draw_rect(Rect2(-6.0, -6.0 + y_off, 6.0, 8.0), Color(0.4, 0.3, 0.2))
        # Wings (white triangles)
        draw_colored_polygon(PackedVector2Array([
                Vector2(2.0, -4.0 + y_off),
                Vector2(10.0, -8.0 + y_off),
                Vector2(2.0, 0.0 + y_off)
        ]), Color(1.0, 1.0, 1.0, 0.9))
        # Aura
        var aura_r := 16.0 + pulse * 2.0
        draw_arc(Vector2.ZERO, aura_r, 0, TAU, 16, Color(1.0, 1.0, 1.0, 0.3), 1.0)


func _draw_treasure() -> void:
        # 5 different treasures, each 10000 points.
        var y_off := -bob_offset
        # Soft glow
        draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.85, 0.3, 0.15))
        match treasure_type:
                TreasureType.TRES_CROWN:
                        # Crown: 3 spikes + band
                        draw_rect(Rect2(-8.0, 0.0 + y_off, 16.0, 4.0), Color(1.0, 0.85, 0.2))
                        for i in range(3):
                                var x := -6.0 + float(i) * 6.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(x, 0.0 + y_off),
                                        Vector2(x + 4.0, 0.0 + y_off),
                                        Vector2(x + 2.0, -6.0 + y_off)
                                ]), Color(1.0, 0.85, 0.2))
                TreasureType.TRES_GOLD:
                        # Gold coins (stack of 3)
                        for i in range(3):
                                draw_circle(Vector2(0, float(i) * 2.0 + y_off - 4.0), 5.0,
                                                        Color(1.0, 0.85, 0.2))
                TreasureType.TRES_CHEST:
                        # Small chest
                        draw_rect(Rect2(-8.0, -4.0 + y_off, 16.0, 10.0), Color(0.6, 0.4, 0.2))
                        draw_rect(Rect2(-8.0, -6.0 + y_off, 16.0, 4.0), Color(0.45, 0.3, 0.15))
                        draw_rect(Rect2(-1.0, 0.0 + y_off, 2.0, 4.0), Color(1.0, 0.85, 0.2))
                TreasureType.TRES_GEM:
                        # Diamond
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -8.0 + y_off),
                                Vector2(7.0, 0.0 + y_off),
                                Vector2(0, 8.0 + y_off),
                                Vector2(-7.0, 0.0 + y_off)
                        ]), Color(0.3, 0.8, 1.0))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0, -8.0 + y_off),
                                Vector2(7.0, 0.0 + y_off),
                                Vector2(0, 0.0 + y_off)
                        ]), Color(0.6, 1.0, 1.0))
                TreasureType.TRES_CUP:
                        # Goblet
                        draw_rect(Rect2(-6.0, -6.0 + y_off, 12.0, 4.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-4.0, -2.0 + y_off, 8.0, 4.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-1.5, 2.0 + y_off, 3.0, 6.0), Color(1.0, 0.85, 0.2))
                        draw_rect(Rect2(-4.0, 8.0 + y_off, 8.0, 2.0), Color(1.0, 0.85, 0.2))


func _draw_exit_door() -> void:
        # Glowing door portal in the wall.
        var alpha := 1.0 if active else 0.5
        # Frame
        draw_rect(Rect2(-18.0, -30.0, 36.0, 60.0), Color(0.3, 0.2, 0.1, alpha))
        # Inner glow (animated)
        var inner_col := Color(0.3, 0.8, 1.0, 0.5 + door_glow_pulse * 0.4)
        draw_rect(Rect2(-14.0, -26.0, 28.0, 52.0), inner_col)
        # Runes on the sides
        for i in range(3):
                var y := -20.0 + float(i) * 18.0
                draw_circle(Vector2(-22.0, y), 2.0, Color(1.0, 0.9, 0.4, alpha))
                draw_circle(Vector2(22.0, y), 2.0, Color(1.0, 0.9, 0.4, alpha))


func _draw_magic_portal() -> void:
        # Swirling portal disc.
        var r := 24.0 + pulse * 4.0
        draw_circle(Vector2.ZERO, r * 1.4, Color(0.4, 0.2, 0.7, 0.20))
        draw_circle(Vector2.ZERO, r, Color(0.6, 0.3, 0.9, 0.5))
        # Swirl lines
        var rot := deg_to_rad(rotation_deg)
        for i in range(6):
                var a := float(i) / 6.0 * TAU + rot
                var inner := Vector2(cos(a), sin(a)) * r * 0.4
                var outer := Vector2(cos(a + 0.6), sin(a + 0.6)) * r * 0.9
                draw_line(inner, outer, Color(0.8, 0.5, 1.0, 0.8), 2.0)


# =========================================================
# Static helpers
# =========================================================

## Factory: create a treasure of given kind at pos.
static func make_treasure(t: int, at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.TREASURE
        c.treasure_type = t
        c.pos = at
        return c


## Factory: create a mine at pos.
static func make_mine(at: Vector2, in_boss: bool = false) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.MINE
        c.pos = at
        c.in_boss_room = in_boss
        return c


## Factory: create a chalice at pos.
static func make_chalice(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.CHALICE
        c.pos = at
        return c


## Factory: create a scepter at pos.
static func make_scepter(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.SCEPTER
        c.pos = at
        c.lightnings_left = 5
        c.lightning_timer_ms = 3000
        return c


## Factory: create a speed-boots pickup at pos.
static func make_speed_boots(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.SPEED_BOOTS
        c.pos = at
        return c


## Factory: create an exit door at pos.
static func make_exit_door(at: Vector2) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.EXIT_DOOR
        c.pos = at
        c.active = false  # activates when all treasures are collected
        return c


## Factory: create a magic portal at pos.
static func make_magic_portal(at: Vector2, enemies_count: int) -> Collectibles:
        var c := Collectibles.new()
        c.kind = Kind.MAGIC_PORTAL
        c.pos = at
        c.portal_enemies_to_spawn = enemies_count
        c.portal_phase = 0
        c.portal_phase_timer_ms = 1000  # 1s open animation
        c.portal_spawn_timer_ms = 0
        return c

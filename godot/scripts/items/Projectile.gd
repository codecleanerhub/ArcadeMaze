## Projectile.gd - Bullet/laser/spell node for both player and boss shots.
## ============================================================
## Godot port of `struct Projectile` (src/Weapon.h) plus the boss-projectile
## rendering code from `Game.cpp`.
##
## 17 unique boss projectile kinds (BossProjKind), each with its own visual
## style (boulder, necro bolt, fireball, webshot, ink spray, dragon breath,
## ghost bolt, blood bolt, eye ray, ghoul claw, spectral fang, cult orb,
## mimic goo, rat swarm, witch hex, twilight blade) plus the BP_NORMAL
## fallback used by the player's own bullets.
##
## Update logic:
##   * Linear motion: pos += dir * delta_t
##   * Homing: while homing_timer > 0, dir is rotated towards target_player_pos
##   * Off-screen culling: deactivates when leaving the play area
##
## Collision is delegated to the caller (Game) for performance and
## flexibility — Projectile only manages its own movement & rendering.
extends Node2D
class_name Projectile

# Mirrors C++ enum BossProjKind.
enum BossProjKind {
        BP_NORMAL,        # generic / player projectile
        BP_BOULDER,       # GOLEM
        BP_NECRO_BOLT,    # LICH
        BP_FIREBALL,      # DEMON
        BP_WEBSHOT,       # SPIDER
        BP_FLESH_CHUNK,   # ABOMINATION
        BP_INK_SPRAY,     # KRAKEN
        BP_DRAGON_BREATH, # DRAGON
        BP_GHOST_BOLT,    # WRAITH_LORD
        BP_BLOOD_BOLT,    # VAMPIRE
        BP_EYE_RAY,       # BEHOLDER
        BP_GHOUL_CLAW,    # GHOUL_LORD
        BP_SPECTRAL_FANG, # SPECTRAL_ALPHA
        BP_CULT_ORB,      # CULT_HERALD
        BP_MIMIC_GOO,     # COLOSSAL_MIMIC
        BP_RAT_SWARM,     # RAT_KING
        BP_WITCH_HEX,     # SUPREME_WITCH
        BP_TWILIGHT_BLADE # TWILIGHT_KNIGHT
}

# Mirrors C++ enum WeaponType.
enum WeaponType { WPN_PISTOL, WPN_SHOTGUN, WPN_ROCKET, WPN_LASER }

@export var bp_kind: int = BossProjKind.BP_NORMAL
@export var weapon_type: int = WeaponType.WPN_PISTOL
@export var power: int = 1
@export var variant: int = 0
@export var homing_timer_ms: int = 0   # >0 = homing projectile (ms remaining)
@export var active: bool = true

# Position in pixels (same convention as C++: top-left origin, +Y down).
var pos: Vector2 = Vector2.ZERO
# Per-frame velocity (already scaled by speed).
var dir: Vector2 = Vector2.ZERO
# Age in milliseconds (used for sinusoidal behaviours, life culling).
var age_ms: int = 0

# Optional reference to a player node for homing. Caller sets this.
var target_node: Node2D = null

# Visual constants (mirrors C++ Game.cpp::drawBossProjectiles).
const _COLORS: Dictionary = {
        BossProjKind.BP_NORMAL:        Color(1.0, 1.0, 1.0),
        BossProjKind.BP_BOULDER:       Color(0.55, 0.45, 0.30),
        BossProjKind.BP_NECRO_BOLT:    Color(0.20, 1.00, 0.30),
        BossProjKind.BP_FIREBALL:      Color(1.00, 0.45, 0.10),
        BossProjKind.BP_WEBSHOT:       Color(0.85, 0.85, 0.85),
        BossProjKind.BP_FLESH_CHUNK:   Color(0.70, 0.45, 0.45),
        BossProjKind.BP_INK_SPRAY:     Color(0.10, 0.10, 0.30),
        BossProjKind.BP_DRAGON_BREATH: Color(1.00, 0.30, 0.05),
        BossProjKind.BP_GHOST_BOLT:    Color(0.30, 1.00, 1.00),
        BossProjKind.BP_BLOOD_BOLT:    Color(0.70, 0.05, 0.10),
        BossProjKind.BP_EYE_RAY:       Color(1.00, 0.30, 0.30),
        BossProjKind.BP_GHOUL_CLAW:    Color(0.85, 0.85, 0.70),
        BossProjKind.BP_SPECTRAL_FANG: Color(0.60, 1.00, 0.70),
        BossProjKind.BP_CULT_ORB:      Color(0.65, 0.20, 0.85),
        BossProjKind.BP_MIMIC_GOO:     Color(0.40, 0.80, 0.20),
        BossProjKind.BP_RAT_SWARM:     Color(0.30, 0.25, 0.20),
        BossProjKind.BP_WITCH_HEX:     Color(0.85, 0.20, 0.85),
        BossProjKind.BP_TWILIGHT_BLADE: Color(0.20, 0.10, 0.30),
}

# Approximate radius (px) per kind (collision + draw size).
const _RADII: Dictionary = {
        BossProjKind.BP_NORMAL:        4.0,
        BossProjKind.BP_BOULDER:       12.0,
        BossProjKind.BP_NECRO_BOLT:    6.0,
        BossProjKind.BP_FIREBALL:      7.0,
        BossProjKind.BP_WEBSHOT:       6.0,
        BossProjKind.BP_FLESH_CHUNK:   8.0,
        BossProjKind.BP_INK_SPRAY:     6.0,
        BossProjKind.BP_DRAGON_BREATH: 7.0,
        BossProjKind.BP_GHOST_BOLT:    6.0,
        BossProjKind.BP_BLOOD_BOLT:    6.0,
        BossProjKind.BP_EYE_RAY:       5.0,
        BossProjKind.BP_GHOUL_CLAW:    7.0,
        BossProjKind.BP_SPECTRAL_FANG: 5.0,
        BossProjKind.BP_CULT_ORB:      8.0,
        BossProjKind.BP_MIMIC_GOO:     7.0,
        BossProjKind.BP_RAT_SWARM:     6.0,
        BossProjKind.BP_WITCH_HEX:     7.0,
        BossProjKind.BP_TWILIGHT_BLADE: 7.0,
}

# Play-area bounds (set by the Game when spawning). Default = whole window.
var bounds := Rect2(0.0, 80.0, 1024.0, 944.0)


func _init() -> void:
        pass


func _ready() -> void:
        pass


# ---- Factory: build a projectile from a fire-angle (C++ makeBossProj) ----

static func make_boss(from: Vector2, angle: float, speed: float,
                power_val: int, kind: int, variant_val: int = 0,
                homing_ms: int = 0) -> Projectile:
        var p := Projectile.new()
        p.pos = from
        p.dir = Vector2(cos(angle) * speed, sin(angle) * speed)
        p.power = power_val
        p.active = true
        p.weapon_type = WeaponType.WPN_PISTOL  # ignored by boss-projectile rendering
        p.bp_kind = kind
        p.variant = variant_val
        p.homing_timer_ms = homing_ms
        p.age_ms = 0
        return p


static func make_player(from: Vector2, angle: float, speed: float,
                power_val: int, weapon_kind: int) -> Projectile:
        var p := Projectile.new()
        p.pos = from
        p.dir = Vector2(cos(angle) * speed, sin(angle) * speed)
        p.power = power_val
        p.active = true
        p.weapon_type = weapon_kind
        p.bp_kind = BossProjKind.BP_NORMAL
        p.age_ms = 0
        return p


# ---- Update: motion + homing + culling ----
# `delta_ms` is the simulated elapsed time in ms (16ms @ 60fps, same as C++).
# `target_pos` is the player pixel position (for homing projectiles only).
func update_step(delta_ms: int, target_pos: Vector2) -> void:
        if not active:
                return
        age_ms += delta_ms

        # Homing: rotate dir towards player while homing_timer_ms > 0.
        if homing_timer_ms > 0:
                homing_timer_ms = maxi(0, homing_timer_ms - delta_ms)
                var to_target: Vector2 = target_pos - pos
                if to_target.length() > 0.001:
                        var desired := to_target.normalized() * dir.length()
                        # Lerp 8% towards the target per frame (≈ partial in-seek of C++).
                        dir = dir.lerp(desired, 0.08)

        # Move (dir is already a per-frame velocity vector, like the C++ code).
        pos += dir

        # Cull if it leaves the play area.
        if pos.x < bounds.position.x - 64 or pos.x > bounds.position.x + bounds.size.x + 64 \
                        or pos.y < bounds.position.y - 64 or pos.y > bounds.position.y + bounds.size.y + 64:
                active = false


# ---- Rendering ----

func _draw() -> void:
        if not active:
                return
        var col: Color = _COLORS.get(bp_kind, Color.WHITE)
        var radius: float = _RADII.get(bp_kind, 4.0)
        # Eye-ray variants use different colors (BEHOLDER).
        if bp_kind == BossProjKind.BP_EYE_RAY:
                match variant:
                        0: col = Color(1.0, 0.2, 0.2)
                        1: col = Color(0.2, 1.0, 0.2)
                        2: col = Color(0.2, 0.4, 1.0)
                        3: col = Color(1.0, 1.0, 0.2)
                        4: col = Color(1.0, 0.2, 1.0)

        # Slight wobble based on age to feel alive.
        var pulse := 1.0 + 0.15 * sin(float(age_ms) * 0.02)
        radius *= pulse

        match bp_kind:
                BossProjKind.BP_BOULDER:
                        # Heavy grey rock with darker outline.
                        draw_circle(Vector2.ZERO, radius, Color(0.35, 0.30, 0.22))
                        draw_circle(Vector2.ZERO, radius * 0.7, col)
                        draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0))
                        _draw_outline(radius, Color(0.15, 0.10, 0.05))
                BossProjKind.BP_NECRO_BOLT:
                        # Green glow + bright core (LICH).
                        draw_circle(Vector2.ZERO, radius * 2.0, Color(col.r, col.g, col.b, 0.20))
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 1.0, 1.0, 0.9))
                BossProjKind.BP_FIREBALL:
                        # Orange with inner yellow core (DEMON). Variant 1 = bigger bomb.
                        var r := radius * (1.4 if variant == 1 else 1.0)
                        draw_circle(Vector2.ZERO, r * 1.5, Color(1.0, 0.4, 0.0, 0.30))
                        draw_circle(Vector2.ZERO, r, col)
                        draw_circle(Vector2.ZERO, r * 0.5, Color(1.0, 1.0, 0.4))
                BossProjKind.BP_WEBSHOT:
                        # Sticky web: white-ish blob with cross threads.
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_line(Vector2(-radius, 0), Vector2(radius, 0), Color(0.4, 0.4, 0.4), 1.0)
                        draw_line(Vector2(0, -radius), Vector2(0, radius), Color(0.4, 0.4, 0.4), 1.0)
                BossProjKind.BP_FLESH_CHUNK:
                        # Reddish meat chunk.
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_circle(Vector2.ZERO - Vector2(radius * 0.3, radius * 0.3),
                                                radius * 0.3, Color(0.85, 0.55, 0.55))
                BossProjKind.BP_INK_SPRAY:
                        # Dark blob with glossy highlight (KRAKEN).
                        draw_circle(Vector2.ZERO, radius * 1.2, col)
                        draw_circle(Vector2.ZERO - Vector2(radius * 0.4, radius * 0.4),
                                                radius * 0.4, Color(0.4, 0.4, 0.6))
                BossProjKind.BP_DRAGON_BREATH:
                        # Bright orange flame puff.
                        draw_circle(Vector2.ZERO, radius * 1.8, Color(1.0, 0.3, 0.0, 0.30))
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 0.9, 0.3))
                BossProjKind.BP_GHOST_BOLT:
                        # Cyan wraith bolt.
                        draw_circle(Vector2.ZERO, radius * 2.0, Color(col.r, col.g, col.b, 0.15))
                        draw_circle(Vector2.ZERO, radius, col)
                BossProjKind.BP_BLOOD_BOLT:
                        # Dark red dart.
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_circle(Vector2.ZERO, radius * 0.5, Color(0.4, 0.0, 0.0))
                BossProjKind.BP_EYE_RAY:
                        # Beholder ray: long thin line + glowing tip.
                        var end := -dir.normalized() * (radius * 3.0)
                        draw_line(end, Vector2.ZERO, col, 2.0)
                        draw_circle(Vector2.ZERO, radius, col)
                BossProjKind.BP_GHOUL_CLAW:
                        # Bone claw: 3 small triangles.
                        for i in range(3):
                                var a := i * 0.4 - 0.4
                                var tip := Vector2(cos(a), sin(a)) * radius * 1.5
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2.ZERO,
                                        tip,
                                        Vector2(cos(a + 0.2), sin(a + 0.2)) * radius * 1.5
                                ]), col)
                BossProjKind.BP_SPECTRAL_FANG:
                        # Cyan fang (long thin triangle).
                        var ang := dir.angle()
                        var tip := Vector2(cos(ang), sin(ang)) * radius * 2.0
                        var perp := Vector2(-sin(ang), cos(ang)) * radius * 0.7
                        draw_colored_polygon(PackedVector2Array([tip, -perp, perp]), col)
                BossProjKind.BP_CULT_ORB:
                        # Purple orb with darker aura.
                        draw_circle(Vector2.ZERO, radius * 1.6, Color(col.r, col.g, col.b, 0.25))
                        draw_circle(Vector2.ZERO, radius, col)
                        draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 1.0, 1.0, 0.7))
                BossProjKind.BP_MIMIC_GOO:
                        # Greenish goo blob.
                        draw_circle(Vector2.ZERO, radius * 1.1, col)
                        draw_circle(Vector2.ZERO, radius * 0.5, Color(0.7, 1.0, 0.4))
                BossProjKind.BP_RAT_SWARM:
                        # Three small dots (RAT_KING swarm).
                        for i in range(3):
                                var off := Vector2((i - 1) * 3.0, 0.0)
                                draw_circle(off, radius * 0.5, col)
                BossProjKind.BP_WITCH_HEX:
                        # Purple curse, spiral for homing variant.
                        draw_circle(Vector2.ZERO, radius * 1.6, Color(col.r, col.g, col.b, 0.30))
                        draw_circle(Vector2.ZERO, radius, col)
                        # Small pentagram-ish cross marks the hex.
                        draw_line(Vector2(-radius * 0.7, -radius * 0.7),
                                          Vector2(radius * 0.7, radius * 0.7),
                                          Color(1.0, 0.4, 1.0), 1.0)
                BossProjKind.BP_TWILIGHT_BLADE:
                        # Shadow blade (long thin dark triangle).
                        var ang := dir.angle()
                        var tip := Vector2(cos(ang), sin(ang)) * radius * 2.2
                        var perp := Vector2(-sin(ang), cos(ang)) * radius * 0.6
                        draw_colored_polygon(PackedVector2Array([tip, -perp, perp]), col)
                _:
                        # Player bullets (BP_NORMAL).
                        match weapon_type:
                                WeaponType.WPN_PISTOL:
                                        draw_circle(Vector2.ZERO, radius, Color(1.0, 1.0, 0.4))
                                WeaponType.WPN_SHOTGUN:
                                        draw_circle(Vector2.ZERO, radius * 1.2, Color(1.0, 0.6, 0.2))
                                WeaponType.WPN_LASER:
                                        # Laser is rendered as a long stretched line.
                                        var line_end := -dir.normalized() * 18.0
                                        draw_line(line_end, Vector2.ZERO, Color(0.4, 0.9, 1.0), 3.0)
                                WeaponType.WPN_ROCKET:
                                        draw_circle(Vector2.ZERO, radius * 1.4, Color(0.8, 0.2, 0.2))
                                        draw_circle(Vector2.ZERO, radius * 0.6, Color(1.0, 0.9, 0.3))


func _draw_outline(radius: float, color: Color) -> void:
        var seg := 16
        var prev := Vector2(radius, 0.0).rotated(0.0)
        for i in range(1, seg + 1):
                var a := (float(i) / float(seg)) * TAU
                var cur := Vector2(cos(a), sin(a)) * radius
                draw_line(prev, cur, color, 1.0)
                prev = cur


# Set global position. In Godot, this node's transform sets the position of the
# projectile on screen — call `position = pos` from the Game's update step.
func sync_position() -> void:
        position = pos

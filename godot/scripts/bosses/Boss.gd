## Boss.gd - End-of-level boss (17 unique types).
## ============================================================
## Godot port of `src/Boss.{h,cpp}`.
##
## 17 boss types, each with its own sprite and shooting pattern. The boss
## spawns on every 4th level (level 4, 8, 12, ...). Type is selected via
## getBossIndex(level) which cycles through 0..16.
##
## Stats:
##   * size:   120..180 px (grows with level, capped at 180)
##   * speed:  1..2 px/frame (always ≤ player speed)
##   * health: 50 + level*20  (level 1=70, level 10=250, level 17=390)
##
## Behaviour:
##   * Diagonal movement, bouncing off the room walls
##   * Type-specific shooting patterns: 1 to 5 projectiles per shot
##   * Some patterns include homing projectiles (WRAITH_LORD, VAMPIRE,
##     SUPREME_WITCH) that pursue the player for a few seconds
##   * attackingTimer triggers a "pulse" animation on the DeformableSprite
##
## Rendering:
##   * Sprite: DeformableSprite (mesh-deformed single frame from
##     `assets/sprites/boss_XXX_sheet.png`, sub-rect 64x64, grid 8x8)
##   * HP bar: positioned above the head, color-coded by HP ratio
##   * If sprite PNG is missing: falls back to render_primitives() which
##     draws the boss with Polygon2D/CircleShape primitives
extends Node2D
class_name Boss

# ---- Boss types (mirrors C++ enum BossType) ----
enum Type {
        BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER,
        BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON,
        BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER,
        BOSS_GHOUL_LORD, BOSS_SPECTRAL_ALPHA, BOSS_CULT_HERALD,
        BOSS_COLOSSAL_MIMIC, BOSS_RAT_KING, BOSS_SUPREME_WITCH,
        BOSS_TWILIGHT_KNIGHT
}

const BOSS_TYPE_COUNT := 17
const MAZE_LEVELS_PER_BOSS := 3
const TOTAL_LEVELS_PER_BOSS := MAZE_LEVELS_PER_BOSS + 1  # 4

const WINDOW_WIDTH := 1024
const WINDOW_HEIGHT := 1024
const UI_HEIGHT := 80

@export var boss_level: int = 4   # 1-based level (4 = first boss level)
@export var boss_type: int = Type.BOSS_GOLEM

# Position (pixel coords, +Y down).
var pos: Vector2 = Vector2.ZERO:
        set(v):
                pos = v
                position = v

# Direction (sign only; magnitude is implicit in speed).
var dx: int = 2
var dy: int = 1

var size: float = 130.0
var speed: int = 1
var health: int = 70
var max_health: int = 70

# Timers (in ms, decremented each frame).
var shoot_timer_ms: int = 0
var attacking_timer_ms: int = 0
var anim_time: float = 0.0

# DeformableSprite node (lazy-init on first render).
var deform_sprite: DeformableSprite = null
var deform_loaded: bool = false

# Sprite ID (e.g. "boss_031" for the GOLEM).
var sprite_id: String = ""

# Signals emitted to the Game.
signal shoot(projectile: Projectile)
signal died(boss: Boss)


# ============================================================
# Static helpers (mirror C++ inline functions in Boss.h)
# ============================================================

static func is_boss_level(level: int) -> bool:
        return (level % TOTAL_LEVELS_PER_BOSS) == 0


static func get_boss_index(level: int) -> int:
        return (level / TOTAL_LEVELS_PER_BOSS) % BOSS_TYPE_COUNT


# Map boss type to its spritesheet ID (assets/sprites/<id>_sheet.png).
# Matches the C++ Boss::getSpriteId() switch exactly.
static func get_sprite_id(t: int) -> String:
        match t:
                Type.BOSS_GOLEM:           return "boss_031"
                Type.BOSS_LICH:            return "boss_032"
                Type.BOSS_DEMON:           return "boss_033"
                Type.BOSS_ABOMINATION:     return "boss_034"
                Type.BOSS_DRAGON:          return "boss_035"
                Type.BOSS_WRAITH_LORD:     return "boss_036"
                Type.BOSS_BEHOLDER:        return "boss_037"
                Type.BOSS_SPIDER:          return "boss_022"
                Type.BOSS_KRAKEN:          return "boss_030"
                Type.BOSS_VAMPIRE:         return "boss_029"
                Type.BOSS_GHOUL_LORD:      return "boss_021"
                Type.BOSS_SPECTRAL_ALPHA:  return "boss_023"
                Type.BOSS_CULT_HERALD:     return "boss_024"
                Type.BOSS_COLOSSAL_MIMIC:  return "boss_025"
                Type.BOSS_RAT_KING:        return "boss_026"
                Type.BOSS_SUPREME_WITCH:   return "boss_027"
                Type.BOSS_TWILIGHT_KNIGHT: return "boss_028"
        return ""


# Descriptive boss name for the room banner.
static func get_boss_name(t: int) -> String:
        match t:
                Type.BOSS_GOLEM:           return "Stone Golem"
                Type.BOSS_LICH:            return "Lich Necromancer"
                Type.BOSS_DEMON:           return "Abyssal Demon"
                Type.BOSS_SPIDER:          return "Giant Spider"
                Type.BOSS_ABOMINATION:     return "Abomination"
                Type.BOSS_KRAKEN:          return "Kraken"
                Type.BOSS_DRAGON:          return "Ancient Dragon"
                Type.BOSS_WRAITH_LORD:     return "Wraith Lord"
                Type.BOSS_VAMPIRE:         return "Vampire Lord"
                Type.BOSS_BEHOLDER:        return "Beholder"
                Type.BOSS_GHOUL_LORD:      return "Ghoul Lord"
                Type.BOSS_SPECTRAL_ALPHA:  return "Spectral Alpha Wolf"
                Type.BOSS_CULT_HERALD:     return "Cult Herald"
                Type.BOSS_COLOSSAL_MIMIC:   return "Colossal Mimic"
                Type.BOSS_RAT_KING:        return "Rat King"
                Type.BOSS_SUPREME_WITCH:   return "Supreme Witch"
                Type.BOSS_TWILIGHT_KNIGHT: return "Twilight Knight"
        return "Unknown"


# ============================================================
# Setup
# ============================================================
func setup(level: int, screen_w: int, screen_h: int) -> void:
        boss_level = level
        boss_type = get_boss_index(level)

        # Size scaling (matches C++ formula).
        if level <= 10:
                size = float(120 + level * 4)        # 124..160
        else:
                size = float(160 + min(20, (level - 10) * 2))  # cap 180

        # Initial position: centered horizontally, below the UI bar.
        pos = Vector2(screen_w / 2.0, UI_HEIGHT + 120.0 + size)

        # Diagonal direction (alternates by level parity).
        dx = 2 if (level % 2 == 0) else -2
        dy = 1 if (level % 3 == 0) else -1

        # Speed cap (≤ player base speed of 2).
        speed = 1 + level / 8
        if speed > 2:
                speed = 2

        # Health (50 + level*20).
        health = 50 + level * 20
        max_health = health

        sprite_id = get_sprite_id(boss_type)

        # Pre-create the DeformableSprite child (lazy loads texture on first render).
        _ensure_deform_sprite()

        # Apply CharacterArt enhancement shader (strong variant for bosses).
        # Boss renders via DeformableSprite (MeshInstance2D, spatial shader)
        # but also has a primitive fallback _draw_primitives() path on self.
        # We apply the canvas_item shader to the Boss node itself so the
        # primitive rendering gets enhanced (rim light, sharpening, depth).
        if CharacterArt:
                CharacterArt.apply_enhancement_to_canvas_item(self, true)


func _ensure_deform_sprite() -> void:
        if deform_sprite != null:
                return
        var ds := DeformableSprite.new()
        add_child(ds)
        deform_sprite = ds


# ============================================================
# Damage / state queries
# ============================================================
func take_damage(dmg: int) -> void:
        health -= dmg


func is_dead() -> bool:
        return health <= 0


# ============================================================
# Update
# ============================================================

# `player_x`/`player_y` are the player's pixel coordinates (for aiming).
# `delta_ms` is the simulated elapsed time (16ms @ 60fps).
# `projectiles_out` is an Array the boss appends new Projectile instances to.
func update_step(player_x: float, player_y: float, delta_ms: int,
                projectiles_out: Array) -> void:
        anim_time += float(delta_ms) * 0.001

        # Decrement attackingTimer.
        if attacking_timer_ms > 16:
                attacking_timer_ms -= 16
        else:
                attacking_timer_ms = 0

        # Diagonal movement.
        pos.x += float(dx) * float(speed)
        pos.y += float(dy) * float(speed)

        # Bounce on room walls.
        if pos.x < size * 0.5 or pos.x > float(WINDOW_WIDTH) - size * 0.5:
                dx = -dx
        if pos.y < UI_HEIGHT + size * 0.5 or pos.y > float(WINDOW_HEIGHT) - size * 0.5:
                dy = -dy

        # Shoot timer.
        shoot_timer_ms += delta_ms
        var base_cd := 2500 - boss_level * 100
        if base_cd < 1000:
                base_cd = 1000
        if shoot_timer_ms > base_cd:
                shoot_timer_ms = 0
                attacking_timer_ms = 500
                _shoot_pattern(player_x, player_y, projectiles_out)

        # Update the deformable sprite.
        if deform_loaded and deform_sprite != null:
                var mode := DeformableSprite.AnimMode.IDLE
                if attacking_timer_ms > 0:
                        mode = DeformableSprite.AnimMode.ATTACK
                var scale_val := size / 64.0
                var draw_x := pos.x - 32.0 * scale_val
                var draw_y := (pos.y - size * 0.25) - 32.0 * scale_val
                deform_sprite.position = Vector2(draw_x, draw_y) - pos  # local offset
                deform_sprite.update(anim_time, mode, scale_val, false)

        position = pos


# ============================================================
# Shooting patterns (per type)
# ============================================================
func _shoot_pattern(player_x: float, player_y: float, out: Array) -> void:
        var dxp := player_x - pos.x
        var dyp := player_y - pos.y
        var dist := sqrt(dxp * dxp + dyp * dyp)
        if dist <= 0.0:
                return
        var base_angle := atan2(dyp, dxp)

        match boss_type:
                Type.BOSS_GOLEM:
                        # 1 heavy slow boulder + 2 small fast side boulders.
                        out.append(Projectile.make_boss(pos, base_angle, 2.5, 2,
                                Projectile.BossProjKind.BP_BOULDER))
                        out.append(Projectile.make_boss(pos, base_angle - 0.5, 3.5, 1,
                                Projectile.BossProjKind.BP_BOULDER))
                        out.append(Projectile.make_boss(pos, base_angle + 0.5, 3.5, 1,
                                Projectile.BossProjKind.BP_BOULDER))

                Type.BOSS_LICH:
                        # 3 green necro bolts in a tight fan.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.25, 5.0, 1,
                                        Projectile.BossProjKind.BP_NECRO_BOLT))
                        # 1/3 chance: slow powerful necro bolt.
                        if randi() % 3 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 2.5, 2,
                                        Projectile.BossProjKind.BP_NECRO_BOLT, 1))

                Type.BOSS_DEMON:
                        # 3 fast fireballs + 50% chance of a slow big bomb.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.35, 5.5, 1,
                                        Projectile.BossProjKind.BP_FIREBALL))
                        if randi() % 2 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 2.0, 3,
                                        Projectile.BossProjKind.BP_FIREBALL, 1))

                Type.BOSS_SPIDER:
                        # 2 slow webshots + 25% chance of 8-way web burst.
                        out.append(Projectile.make_boss(pos, base_angle - 0.2, 2.5, 1,
                                Projectile.BossProjKind.BP_WEBSHOT))
                        out.append(Projectile.make_boss(pos, base_angle + 0.2, 2.5, 1,
                                Projectile.BossProjKind.BP_WEBSHOT))
                        if randi() % 4 == 0:
                                for i in range(8):
                                        var a := float(i) * (PI / 4.0)
                                        out.append(Projectile.make_boss(pos, a, 3.0, 1,
                                                Projectile.BossProjKind.BP_WEBSHOT, 1))

                Type.BOSS_ABOMINATION:
                        # 3 flesh chunks with random spread.
                        for i in range(-1, 2):
                                var ang_var := float(randi_range(-20, 40) - 20) * PI / 180.0
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.4 + ang_var, 4.0, 1,
                                        Projectile.BossProjKind.BP_FLESH_CHUNK))

                Type.BOSS_KRAKEN:
                        # 2 ink sprays + 2 slow powerful tentacles.
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 3.0, 1,
                                Projectile.BossProjKind.BP_INK_SPRAY))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 3.0, 1,
                                Projectile.BossProjKind.BP_INK_SPRAY))
                        out.append(Projectile.make_boss(pos, base_angle - 0.1, 1.8, 2,
                                Projectile.BossProjKind.BP_INK_SPRAY, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.1, 1.8, 2,
                                Projectile.BossProjKind.BP_INK_SPRAY, 1))

                Type.BOSS_DRAGON:
                        # Wide 5-shot fire breath.
                        for i in range(-2, 3):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.18, 6.0, 1,
                                        Projectile.BossProjKind.BP_DRAGON_BREATH))

                Type.BOSS_WRAITH_LORD:
                        # 2 ghost bolts + 1 short homing (1500ms).
                        out.append(Projectile.make_boss(pos, base_angle - 0.2, 4.5, 1,
                                Projectile.BossProjKind.BP_GHOST_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle + 0.2, 4.5, 1,
                                Projectile.BossProjKind.BP_GHOST_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_GHOST_BOLT, 1, 1500))

                Type.BOSS_VAMPIRE:
                        # 3 blood bolts + 1 medium homing (2000ms).
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.25, 5.0, 1,
                                        Projectile.BossProjKind.BP_BLOOD_BOLT))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_BLOOD_BOLT, 1, 2000))

                Type.BOSS_BEHOLDER:
                        # 4 eye rays (variants 0..3 in a row) + 33% chance of a powerful central ray.
                        for i in range(4):
                                var ang := base_angle + (float(i) - 1.5) * 0.3
                                out.append(Projectile.make_boss(pos, ang, 6.0, 1,
                                        Projectile.BossProjKind.BP_EYE_RAY, i))
                        if randi() % 3 == 0:
                                out.append(Projectile.make_boss(pos, base_angle, 4.0, 2,
                                        Projectile.BossProjKind.BP_EYE_RAY, 4))

                Type.BOSS_GHOUL_LORD:
                        # 3 bone claws.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.3, 4.5, 1,
                                        Projectile.BossProjKind.BP_GHOUL_CLAW))

                Type.BOSS_SPECTRAL_ALPHA:
                        # 2 fast spectral fangs.
                        out.append(Projectile.make_boss(pos, base_angle - 0.15, 5.5, 1,
                                Projectile.BossProjKind.BP_SPECTRAL_FANG))
                        out.append(Projectile.make_boss(pos, base_angle + 0.15, 5.5, 1,
                                Projectile.BossProjKind.BP_SPECTRAL_FANG))

                Type.BOSS_CULT_HERALD:
                        # 1 powerful central cult orb + 2 small side orbs.
                        out.append(Projectile.make_boss(pos, base_angle, 3.5, 2,
                                Projectile.BossProjKind.BP_CULT_ORB))
                        out.append(Projectile.make_boss(pos, base_angle - 0.4, 5.0, 1,
                                Projectile.BossProjKind.BP_CULT_ORB, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.4, 5.0, 1,
                                Projectile.BossProjKind.BP_CULT_ORB, 1))

                Type.BOSS_COLOSSAL_MIMIC:
                        # 3 sticky goo streams with random spread.
                        for i in range(-1, 2):
                                var ang_var := float(randi_range(-15, 30) - 15) * PI / 180.0
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.3 + ang_var, 3.5, 1,
                                        Projectile.BossProjKind.BP_MIMIC_GOO))

                Type.BOSS_RAT_KING:
                        # 3 small rats in slightly different directions.
                        for i in range(-1, 2):
                                out.append(Projectile.make_boss(pos, base_angle + float(i) * 0.5, 4.0, 1,
                                        Projectile.BossProjKind.BP_RAT_SWARM))

                Type.BOSS_SUPREME_WITCH:
                        # 2 decoy hexes + 1 long homing HEX (3000ms).
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 4.0, 1,
                                Projectile.BossProjKind.BP_WITCH_HEX, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 4.0, 1,
                                Projectile.BossProjKind.BP_WITCH_HEX, 1))
                        out.append(Projectile.make_boss(pos, base_angle, 3.0, 2,
                                Projectile.BossProjKind.BP_WITCH_HEX, 0, 3000))

                Type.BOSS_TWILIGHT_KNIGHT:
                        # 1 powerful shadow blade + 2 small fast ones.
                        out.append(Projectile.make_boss(pos, base_angle, 4.0, 2,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE))
                        out.append(Projectile.make_boss(pos, base_angle - 0.3, 6.0, 1,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE, 1))
                        out.append(Projectile.make_boss(pos, base_angle + 0.3, 6.0, 1,
                                Projectile.BossProjKind.BP_TWILIGHT_BLADE, 1))


# ============================================================
# Rendering
# ============================================================
func _draw() -> void:
        # Lazy-load the DeformableSprite's texture.
        if not deform_loaded and sprite_id != "" and deform_sprite != null:
                var path := "res://assets/sprites/" + sprite_id + "_sheet.png"
                deform_loaded = deform_sprite.load_subrect(path, 0, 0, 64, 64)
                if deform_loaded:
                        deform_sprite.set_grid_size(8, 8)

        # Draw the deformable sprite (it's a child node, draws itself).
        # If not loaded, fall back to procedural primitives drawn in this node's _draw.
        if not deform_loaded:
                _draw_primitives()

        # HP bar (always drawn on the parent so it stays in screen-space relative
        # to the boss position).
        _draw_hp_bar()


func _draw_hp_bar() -> void:
        # HP bar sits above the boss's head.
        var bar_y := -size * 1.125 - 18.0
        var bar_w := size
        var bar_h := 12.0
        # Background.
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h),
                          Color(0.12, 0.0, 0.0), false, 2.0, Color(0.39, 0.0, 0.0))
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.12, 0.0, 0.0))
        # Foreground (color-coded).
        var ratio := float(health) / float(max_health) if max_health > 0 else 0.0
        var col := Color(0.31, 0.86, 0.31) if ratio > 0.5 \
                          else Color(0.86, 0.71, 0.16) if ratio > 0.25 \
                          else Color(0.86, 0.16, 0.16)
        draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * ratio, bar_h), col)


# ------------------------------------------------------------
# Procedural fallback (matches C++ Boss::renderPrimitives)
# Each boss type has its own distinctive primitive drawing.
# ------------------------------------------------------------
func _draw_primitives() -> void:
        var px := 0.0  # Local origin is (0,0); position is already applied.
        var py := 0.0
        var outline := Color(0.04, 0.04, 0.04)

        # Mouth animation (sinusoidal).
        var mouth_open := (sin(anim_time * 4.0) + 1.0) * 0.5
        var mouth_h := size / 6.0 + mouth_open * size / 6.0

        match boss_type:
                Type.BOSS_GOLEM:
                        _draw_golem(px, py, outline)
                Type.BOSS_LICH:
                        _draw_lich(px, py, outline, mouth_h)
                Type.BOSS_DEMON:
                        _draw_demon(px, py, outline)
                Type.BOSS_SPIDER:
                        _draw_spider(px, py, outline)
                Type.BOSS_ABOMINATION:
                        _draw_abomination(px, py, outline)
                Type.BOSS_KRAKEN:
                        _draw_kraken(px, py, outline)
                Type.BOSS_DRAGON:
                        _draw_dragon(px, py, outline)
                Type.BOSS_WRAITH_LORD:
                        _draw_wraith_lord(px, py, outline)
                Type.BOSS_VAMPIRE:
                        _draw_vampire(px, py, outline)
                Type.BOSS_BEHOLDER:
                        _draw_beholder(px, py, outline)
                Type.BOSS_GHOUL_LORD:
                        _draw_ghoul_lord(px, py, outline)
                Type.BOSS_SPECTRAL_ALPHA:
                        _draw_spectral_alpha(px, py, outline)
                Type.BOSS_CULT_HERALD:
                        _draw_cult_herald(px, py, outline)
                Type.BOSS_COLOSSAL_MIMIC:
                        _draw_colossal_mimic(px, py, outline)
                Type.BOSS_RAT_KING:
                        _draw_rat_king(px, py, outline)
                Type.BOSS_SUPREME_WITCH:
                        _draw_supreme_witch(px, py, outline)
                Type.BOSS_TWILIGHT_KNIGHT:
                        _draw_twilight_knight(px, py, outline)


# --- Individual primitive renderers (compact translations of C++ code) ---

func _draw_golem(px: float, py: float, outline: Color) -> void:
        var rock := Color(0.39, 0.39, 0.43)
        draw_rect(Rect2(px - size * 0.5, py - size * 0.4, size, size * 0.8), rock)
        var arm_off := sin(anim_time * 3.0) * 10.0
        draw_rect(Rect2(px - size * 0.8, py - size * 0.2 + arm_off,
                                        size * 0.3, size * 0.6), Color(0.24, 0.24, 0.27))
        draw_rect(Rect2(px + size * 0.5, py - size * 0.2 - arm_off,
                                        size * 0.3, size * 0.6), Color(0.24, 0.24, 0.27))
        draw_rect(Rect2(px - size * 0.25, py - size * 0.8, size * 0.5, size * 0.5), rock)
        # Eyes (pulsing green).
        var eb := 150.0 + sin(anim_time * 10.0) * 105.0
        var eye_c := Color(0.0, eb / 255.0, 50.0 / 255.0)
        draw_circle(Vector2(px - size * 0.25, py - size * 0.6), size / 12.0, eye_c)
        draw_circle(Vector2(px + size * 0.25, py - size * 0.6), size / 12.0, eye_c)


func _draw_lich(px: float, py: float, outline: Color, mouth_h: float) -> void:
        # Robe (purple, animated wave).
        var wave := sin(anim_time * 3.0) * 10.0
        var robe_pts := PackedVector2Array([
                Vector2(px, py - size * 0.5),
                Vector2(px + size * 0.5 + wave, py),
                Vector2(px + size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.5 - wave, py),
        ])
        draw_colored_polygon(robe_pts, Color(0.16, 0.08, 0.24))
        # Skull.
        draw_circle(Vector2(px, py - size * 0.33), size / 3.0, Color(0.86, 0.86, 0.78))
        # Eyes.
        draw_circle(Vector2(px - size * 0.13, py - size * 0.33), size / 14.0, Color(1.0, 0.0, 0.0))
        draw_circle(Vector2(px + size * 0.13, py - size * 0.33), size / 14.0, Color(1.0, 0.0, 0.0))
        # Mouth.
        draw_rect(Rect2(px - size * 0.2, py + size * 0.125, size * 0.4, mouth_h * 0.5), Color.BLACK)


func _draw_demon(px: float, py: float, outline: Color) -> void:
        # Wings (flapping).
        var flap := sin(anim_time * 8.0) * 0.4 + 0.8
        var wing_pts := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.25),
                Vector2(px - size * 1.2, py - size * 0.5 * flap),
                Vector2(px - size * 1.1, py + size * 0.25 * flap),
                Vector2(px - size * 0.33, py + size * 0.16),
        ])
        draw_colored_polygon(wing_pts, Color(0.31, 0.04, 0.04))
        var wing_pts_r := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.25),
                Vector2(px + size * 1.2, py - size * 0.5 * flap),
                Vector2(px + size * 1.1, py + size * 0.25 * flap),
                Vector2(px + size * 0.33, py + size * 0.16),
        ])
        draw_colored_polygon(wing_pts_r, Color(0.31, 0.04, 0.04))
        # Body.
        draw_circle(Vector2(px, py), size * 0.5, Color(0.59, 0.12, 0.12))
        # Horns.
        var horn_l := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.5),
                Vector2(px - size * 0.5, py - size * 0.8),
                Vector2(px - size * 0.25, py - size * 0.7),
        ])
        draw_colored_polygon(horn_l, outline)
        var horn_r := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.5, py - size * 0.8),
                Vector2(px + size * 0.25, py - size * 0.7),
        ])
        draw_colored_polygon(horn_r, outline)
        # Eyes.
        draw_circle(Vector2(px - size * 0.25 - size * 0.1, py - size * 0.16), size / 10.0, Color.YELLOW)
        draw_circle(Vector2(px + size * 0.25 - size * 0.1, py - size * 0.16), size / 10.0, Color.YELLOW)


func _draw_spider(px: float, py: float, outline: Color) -> void:
        var carapace := Color(0.16, 0.0, 0.20)
        # 8 legs.
        for i in range(4):
                var a1 := deg_to_rad(45.0 + i * 20.0)
                var a2 := deg_to_rad(-45.0 - i * 20.0)
                var leg_move := sin(anim_time * 6.0 + i) * 10.0
                _draw_leg(px - size * 0.25, py + leg_move, a1, size * 0.5, carapace)
                _draw_leg(px + size * 0.25, py - leg_move, a2, size * 0.5, carapace)
        # Abdomen.
        draw_circle(Vector2(px, py - size * 0.25), size * 0.5, carapace)
        # Head.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.25, Color(0.24, 0.0, 0.27))
        # Eyes.
        var eb := 150.0 + sin(anim_time * 8.0) * 105.0
        var eye_c := Color(eb / 255.0, 0.0, 0.0)
        draw_circle(Vector2(px - size * 0.05, py - size * 0.625), size / 20.0, eye_c)
        draw_circle(Vector2(px + size * 0.13, py - size * 0.625), size / 20.0, eye_c)


func _draw_leg(x: float, y: float, angle: float, length: float, color: Color) -> void:
        var end := Vector2(x + cos(angle) * length, y + sin(angle) * length)
        draw_line(Vector2(x, y), end, color, size / 16.0)


func _draw_abomination(px: float, py: float, outline: Color) -> void:
        var flesh := Color(0.55, 0.63, 0.47)
        # Body.
        draw_rect(Rect2(px - size * 0.4, py - size * 0.5, size * 0.8, size), flesh)
        # Arms.
        var arm := sin(anim_time * 2.0) * 15.0
        draw_rect(Rect2(px - size * 0.7, py - size * 0.33 + arm, size * 0.3, size * 0.7), flesh)
        draw_rect(Rect2(px + size * 0.4, py - size * 0.33 - arm, size * 0.3, size * 0.7), flesh)
        # Head.
        draw_rect(Rect2(px - size * 0.2, py - size * 0.9, size * 0.4, size * 0.4), flesh)
        # Bolts.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.8, size * 0.1, size * 0.1), Color(0.71, 0.71, 0.71))
        draw_rect(Rect2(px + size * 0.2, py - size * 0.8, size * 0.1, size * 0.1), Color(0.71, 0.71, 0.71))
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.75), size / 14.0, Color(0.20, 0.20, 0.20))
        draw_circle(Vector2(px + size * 0.1, py - size * 0.75), size / 14.0, Color(0.20, 0.20, 0.20))


func _draw_kraken(px: float, py: float, outline: Color) -> void:
        var skin := Color(0.0, 0.39, 0.39)
        # 8 tentacles.
        for i in range(8):
                var angle := float(i) * (PI / 4.0) + sin(anim_time * 2.0 + i) * 0.2
                var end := Vector2(px + cos(angle) * size * 0.5, py + sin(angle) * size * 0.5)
                draw_line(Vector2(px, py), end, skin, size * 0.1)
        # Body.
        draw_circle(Vector2(px, py), size * 0.5, skin)
        # Eyes.
        draw_circle(Vector2(px - size * 0.25, py - size * 0.25), size / 10.0, Color.YELLOW)
        draw_circle(Vector2(px + size * 0.25, py - size * 0.25), size / 10.0, Color.YELLOW)


func _draw_dragon(px: float, py: float, outline: Color) -> void:
        var bone := Color(0.78, 0.78, 0.71)
        var flap := sin(anim_time * 6.0) * 0.3 + 0.8
        # Wings.
        var wing_l := PackedVector2Array([
                Vector2(px - size * 0.25, py - size * 0.33),
                Vector2(px - size, py - size * 0.5 * flap),
                Vector2(px - size * 0.9, py + size * 0.16 * flap),
                Vector2(px - size * 0.25, py),
        ])
        draw_colored_polygon(wing_l, Color(0.20, 0.20, 0.20))
        var wing_r := PackedVector2Array([
                Vector2(px + size * 0.25, py - size * 0.33),
                Vector2(px + size, py - size * 0.5 * flap),
                Vector2(px + size * 0.9, py + size * 0.16 * flap),
                Vector2(px + size * 0.25, py),
        ])
        draw_colored_polygon(wing_r, Color(0.20, 0.20, 0.20))
        # Body.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.2, size * 0.6, size * 0.6), bone)
        # Head.
        var head_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size),
                Vector2(px - size * 0.25, py - size * 1.1),
                Vector2(px - size * 0.25, py - size * 0.9),
                Vector2(px - size * 0.5, py - size * 0.9),
        ])
        draw_colored_polygon(head_pts, bone)
        # Eye.
        draw_circle(Vector2(px - size * 0.45, py - size * 0.95), size / 20.0, Color.RED)


func _draw_wraith_lord(px: float, py: float, outline: Color) -> void:
        var armor := Color(0.39, 0.39, 0.59)
        # Cloak.
        var wave := sin(anim_time * 4.0) * 15.0
        var cloak_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px + size * 0.16, py + size * 0.33 - wave * 0.5),
                Vector2(px - size * 0.16, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.33 + wave * 0.5),
        ])
        draw_colored_polygon(cloak_pts, Color(0.08, 0.08, 0.16, 0.86))
        # Helmet.
        draw_rect(Rect2(px - size * 0.2, py - size * 0.6, size * 0.4, size * 0.5), armor)
        # Horns.
        var horn_l := PackedVector2Array([
                Vector2(px - size * 0.2, py - size * 0.6),
                Vector2(px - size * 0.4, py - size * 0.8),
                Vector2(px - size * 0.2, py - size * 0.5),
        ])
        draw_colored_polygon(horn_l, armor)
        var horn_r := PackedVector2Array([
                Vector2(px + size * 0.2, py - size * 0.6),
                Vector2(px + size * 0.4, py - size * 0.8),
                Vector2(px + size * 0.2, py - size * 0.5),
        ])
        draw_colored_polygon(horn_r, armor)
        # Eyes.
        var eb := 150.0 + sin(anim_time * 5.0) * 105.0
        var eye_c := Color(0.0, eb / 255.0, eb / 255.0, 0.78)
        draw_circle(Vector2(px - size * 0.2, py - size * 0.45), size / 14.0, eye_c)
        draw_circle(Vector2(px + size * 0.1, py - size * 0.45), size / 14.0, eye_c)


func _draw_vampire(px: float, py: float, outline: Color) -> void:
        var skin := Color(0.90, 0.90, 0.98)
        # Cloak.
        var wave := sin(anim_time * 3.0) * 10.0
        var cloak_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.25),
                Vector2(px + size * 0.5, py - size * 0.25),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.5),
        ])
        draw_colored_polygon(cloak_pts, Color(0.47, 0.0, 0.0))
        # Collar.
        draw_rect(Rect2(px - size * 0.15, py - size * 0.3, size * 0.3, size * 0.1), Color.WHITE)
        # Head.
        draw_circle(Vector2(px, py - size * 0.33), size * 0.33, skin)
        # Hair.
        draw_rect(Rect2(px - size * 0.3, py - size * 0.5, size * 0.6, size * 0.2), Color.BLACK)
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.33), size / 14.0, Color.RED)
        draw_circle(Vector2(px + size * 0.1, py - size * 0.33), size / 14.0, Color.RED)


func _draw_beholder(px: float, py: float, outline: Color) -> void:
        var body_col := Color(0.39, 0.20, 0.20)
        # Pulsating body.
        var pulse := 1.0 + sin(anim_time * 4.0) * 0.1
        draw_circle(Vector2(px, py), size * 0.5 * pulse, body_col)
        # Central eye.
        draw_circle(Vector2(px, py), size * 0.25, Color.WHITE)
        # Pupil that roams.
        var pupil := Vector2(px + cos(anim_time * 2.0) * size * 0.05,
                                                  py + sin(anim_time * 2.0) * size * 0.05)
        draw_circle(pupil, size * 0.0625, Color.BLACK)
        draw_circle(pupil, size * 0.03125, Color.RED)
        # 8 satellite eyes on stalks.
        for i in range(8):
                var a := float(i) * (PI / 4.0) + sin(anim_time * 3.0 + i) * 0.3
                var tx := px + cos(a) * size * 0.5
                var ty := py + sin(a) * size * 0.5
                draw_line(Vector2(px, py), Vector2(tx, ty), body_col, 2.0)
                draw_circle(Vector2(tx, ty), size / 12.0, Color.WHITE)
                draw_circle(Vector2(tx, ty), size / 24.0, Color.BLACK)


func _draw_ghoul_lord(px: float, py: float, outline: Color) -> void:
        var bone := Color(0.86, 0.86, 0.78)
        # Aura.
        draw_circle(Vector2(px, py), size * 0.5 + 10.0, Color(0.31, 1.0, 0.31, 0.16))
        # Body.
        draw_rect(Rect2(px - size * 0.4, py - size * 0.5, size * 0.8, size), bone)
        # Arms.
        var arm := sin(anim_time * 2.0) * 15.0
        draw_rect(Rect2(px - size * 0.6, py - size * 0.25 + arm, size * 0.2, size * 0.6), bone)
        draw_rect(Rect2(px + size * 0.4, py - size * 0.25 - arm, size * 0.2, size * 0.6), bone)
        # Head.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.33, bone)
        # Crown spikes.
        for i in range(5):
                var sx := px - size * 0.33 + float(i) * (size * 0.66) / 4.0
                var spike := PackedVector2Array([
                        Vector2(sx, py - size * 0.8),
                        Vector2(sx + size * 0.083, py - size * 0.8),
                        Vector2(sx + size * 0.042, py - size * 0.8 - size * 0.125),
                ])
                draw_colored_polygon(spike, Color(0.94, 0.94, 0.86))
        # Eyes.
        draw_circle(Vector2(px - size * 0.2, py - size * 0.6), size / 14.0, Color(1.0, 0.20, 0.20))
        draw_circle(Vector2(px + size * 0.1, py - size * 0.6), size / 14.0, Color(1.0, 0.20, 0.20))


func _draw_spectral_alpha(px: float, py: float, outline: Color) -> void:
        var smoke := Color(0.47, 0.47, 0.55, 0.78)
        # 6 smoke puffs.
        for i in range(6):
                var a := float(i) * (PI / 3.0) + anim_time
                var puff_pos := Vector2(px - size * 0.5 + cos(a) * size * 0.33,
                                                                  py - size * 0.33 + sin(a) * size * 0.25)
                draw_circle(puff_pos, size * 0.25, smoke)
        # Body.
        var body_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py + size * 0.25),
                Vector2(px - size * 0.33, py - size * 0.25),
                Vector2(px + size * 0.25, py - size * 0.25),
                Vector2(px + size * 0.5, py),
                Vector2(px + size * 0.33, py + size * 0.25),
        ])
        draw_colored_polygon(body_pts, Color(0.35, 0.35, 0.43, 0.90))
        # Head.
        draw_circle(Vector2(px + size * 0.25, py - size * 0.33), size * 0.25, Color(0.43, 0.43, 0.51, 0.90))
        # Ear.
        var ear := PackedVector2Array([
                Vector2(px + size * 0.25, py - size * 0.33),
                Vector2(px + size * 0.2, py - size * 0.5),
                Vector2(px + size * 0.33, py - size * 0.33),
        ])
        draw_colored_polygon(ear, Color(0.35, 0.35, 0.43, 0.90))
        # Eye.
        draw_circle(Vector2(px + size * 0.33, py - size * 0.25), size / 20.0, Color(0.59, 1.0, 0.59))


func _draw_cult_herald(px: float, py: float, outline: Color) -> void:
        # Robe.
        var wave := sin(anim_time * 3.0) * 15.0
        var robe_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33 + wave, py + size * 0.5),
                Vector2(px + size * 0.16, py + size * 0.33),
                Vector2(px - size * 0.16, py + size * 0.5),
                Vector2(px - size * 0.33 - wave, py + size * 0.33),
        ])
        draw_colored_polygon(robe_pts, Color(0.24, 0.0, 0.31))
        # Hood.
        draw_circle(Vector2(px, py - size * 0.66), size * 0.33, Color(0.16, 0.0, 0.24))
        # Face (dark).
        draw_circle(Vector2(px, py - size * 0.55), size * 0.16, Color.BLACK)
        # Eyes (golden).
        draw_circle(Vector2(px - size * 0.05, py - size * 0.58), size / 24.0, Color(1.0, 0.84, 0.0))
        draw_circle(Vector2(px + size * 0.08, py - size * 0.58), size / 24.0, Color(1.0, 0.84, 0.0))
        # Staff.
        draw_rect(Rect2(px + size * 0.4, py - size * 0.33, size * 0.083, size * 0.8), Color(0.47, 0.31, 0.16))
        # Sigil.
        draw_circle(Vector2(px + size * 0.43, py - size * 0.4), size * 0.1, Color(0.71, 0.20, 0.86, 0.78))


func _draw_colossal_mimic(px: float, py: float, outline: Color) -> void:
        var wood := Color(0.43, 0.27, 0.12)
        # Body (chest).
        draw_rect(Rect2(px - size * 0.5, py - size * 0.33, size, size * 0.8), wood)
        # Lid.
        var lid_pts := PackedVector2Array([
                Vector2(px - size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.5, py - size * 0.33),
                Vector2(px + size * 0.33, py - size * 0.8),
                Vector2(px - size * 0.33, py - size * 0.8),
        ])
        draw_colored_polygon(lid_pts, Color(0.31, 0.20, 0.08))
        # Maw (black).
        draw_rect(Rect2(px - size * 0.4, py - size * 0.125, size * 0.8, size * 0.25), Color.BLACK)
        # 8 teeth.
        for i in range(8):
                var tw := size * 0.8 / 8.0
                var tooth := PackedVector2Array([
                        Vector2(px - size * 0.4 + float(i) * tw, py - size * 0.125),
                        Vector2(px - size * 0.4 + float(i + 1) * tw, py - size * 0.125),
                        Vector2(px - size * 0.4 + float(i) * tw + tw * 0.5, py),
                ])
                draw_colored_polygon(tooth, Color(1.0, 1.0, 0.86))
        # Tongue.
        var tongue := PackedVector2Array([
                Vector2(px - size * 0.125, py),
                Vector2(px + size * 0.125, py),
                Vector2(px + size * 0.083, py + size * 0.16),
                Vector2(px - size * 0.083, py + size * 0.16),
        ])
        draw_colored_polygon(tongue, Color(0.86, 0.31, 0.47))
        # Bands.
        draw_rect(Rect2(px - size * 0.33, py - size * 0.33, size * 0.083, size * 0.8), Color(0.78, 0.78, 0.78))
        draw_rect(Rect2(px + size * 0.25, py - size * 0.33, size * 0.083, size * 0.8), Color(0.78, 0.78, 0.78))


func _draw_rat_king(px: float, py: float, outline: Color) -> void:
        var fur := Color(0.31, 0.27, 0.24)
        # 5 surrounding rats.
        for i in range(5):
                var a := float(i) * (TAU / 5.0) + anim_time * 0.5
                var rat_pos := Vector2(px + cos(a) * size * 0.33, py + sin(a) * size * 0.33)
                draw_circle(rat_pos, size * 0.2, fur)
                draw_circle(rat_pos + Vector2(size * 0.07, 0), size * 0.05, Color.RED)
        # Central body.
        draw_circle(Vector2(px, py), size * 0.33, Color(0.24, 0.20, 0.16))
        # Crown spikes.
        for i in range(5):
                var sx := px - size * 0.25 + float(i) * size * 0.125
                var spike := PackedVector2Array([
                        Vector2(sx, py - size * 0.33),
                        Vector2(sx + size * 0.083, py - size * 0.33),
                        Vector2(sx + size * 0.042, py - size * 0.5),
                ])
                draw_colored_polygon(spike, Color(0.94, 0.94, 0.86))
        # Eyes.
        draw_circle(Vector2(px - size * 0.125, py - size * 0.16), size / 16.0, Color(1.0, 0.12, 0.12))
        draw_circle(Vector2(px + size * 0.063, py - size * 0.16), size / 16.0, Color(1.0, 0.12, 0.12))


func _draw_supreme_witch(px: float, py: float, outline: Color) -> void:
        var robe := Color(0.16, 0.31, 0.16)
        # 6 vines rotating.
        for i in range(6):
                var a := float(i) * (PI / 3.0) + anim_time
                var end := Vector2(px + cos(a) * size * 0.33, py + sin(a) * size * 0.33)
                draw_line(Vector2(px, py), end, Color(0.24, 0.47, 0.24), size * 0.083)
        # Robe.
        var wave := sin(anim_time * 2.0) * 12.0
        var robe_pts := PackedVector2Array([
                Vector2(px, py - size * 0.33),
                Vector2(px + size * 0.5 + wave, py),
                Vector2(px + size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.33, py + size * 0.5),
                Vector2(px - size * 0.5 - wave, py),
        ])
        draw_colored_polygon(robe_pts, robe)
        # Face.
        draw_circle(Vector2(px, py - size * 0.33), size * 0.25, Color(0.59, 0.78, 0.47))
        # Hat.
        var hat := PackedVector2Array([
                Vector2(px - size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.083, py - size),
        ])
        draw_colored_polygon(hat, Color(0.08, 0.08, 0.08))
        # Eyes.
        draw_circle(Vector2(px - size * 0.1, py - size * 0.42), size / 24.0, Color(1.0, 1.0, 0.39))
        draw_circle(Vector2(px + size * 0.03, py - size * 0.42), size / 24.0, Color(1.0, 1.0, 0.39))


func _draw_twilight_knight(px: float, py: float, outline: Color) -> void:
        var armor := Color(0.08, 0.08, 0.14)
        # Body.
        draw_rect(Rect2(px - size * 0.375, py - size * 0.375, size * 0.75, size * 0.75), armor)
        # Pulsing aura.
        var pulse := 1.0 + sin(anim_time * 3.0) * 0.1
        draw_circle(Vector2(px, py), size * 0.5 * pulse, Color(0.0, 0.0, 0.12, 0.39))
        # Chest.
        draw_rect(Rect2(px - size * 0.25, py - size * 0.16, size * 0.5, size * 0.33), Color(0.16, 0.16, 0.24))
        # Helmet.
        draw_rect(Rect2(px - size * 0.25, py - size * 0.8, size * 0.5, size * 0.4), armor)
        # Visor.
        draw_rect(Rect2(px - size * 0.16, py - size * 0.55, size * 0.33, size * 0.0625), Color(0.59, 0.20, 0.86))
        # Shield.
        draw_circle(Vector2(px - size * 0.5, py), size * 0.25, Color(0.12, 0.12, 0.20))
        # Lance.
        draw_rect(Rect2(px + size * 0.33, py - size * 0.5, size * 0.083, size), Color(0.71, 0.71, 0.78))
        # Lance tip.
        var tip := PackedVector2Array([
                Vector2(px + size * 0.33, py - size * 0.5),
                Vector2(px + size * 0.41, py - size * 0.5),
                Vector2(px + size * 0.375, py - size * 0.625),
        ])
        draw_colored_polygon(tip, Color(0.86, 0.86, 0.94))


# ============================================================
# Sprite loading (static, called once by Game::init)
# ============================================================

# In the C++ version, Boss::loadAllSprites caches SpriteSheets. In Godot this
# responsibility is delegated to the SpriteManager autoload, which loads all
# `*_sheet.png` files at startup. The Boss simply looks up its sprite by ID.
# For the DeformableSprite path we lazy-load the texture on first render.

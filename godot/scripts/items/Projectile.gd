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

const C = preload("res://scripts/core/GameConstants.gd")

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

        # TASK 22 — FORME tematiche per boss (flag di rollback:
        # GameConstants.BOSS_PROJ_THEMED_ENABLED = false -> disegno legacy
        # identico a prima). Solo estetica: raggio di collisione invariato.
        if C.BOSS_PROJ_THEMED_ENABLED and bp_kind != BossProjKind.BP_NORMAL:
                _draw_themed(col, radius)
                return

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


# ----------------------------------------------------------------------------
# TASK 22 — Proiettili boss tematici PER FORMA (non solo colore).
# Ogni boss ha un proiettile riconoscibile a colpo d'occhio:
#   GOLEM=masso roccioso rotante, LICH=teschio necrotico luminoso,
#   DEMON=palla di fiamma a goccia, SPIDER=disco-ragnatela,
#   ABOMINATION=brandello di carne irregolare, KRAKEN=getto d'inchiostro,
#   DRAGON=lingua di fiamma allungata, WRAITH=fantasma dall'orlo ondulato,
#   VAMPIRE=dardo-pipistrello, BEHOLDER=raggio oculare affusolato,
#   GHOUL=artigli ricurvi, SPECTRAL=zanna a mezzaluna, CULT=orbo sigillato,
#   MIMIC=melma gocciolante, RAT=topi in corsa, WITCH=sfera di cristallo,
#   TWILIGHT=pugnale ombroso rotante.
# Tutto procedurale (polyline/polygon/arc): NESSUN asset aggiuntivo.
# Le forme occupano ~<=2.2*radius per coerenza visiva con l'hitbox
# (che resta invariata: puro restyling).
# ----------------------------------------------------------------------------

func _t() -> float:
        return float(age_ms) * 0.001


func _dir_angle() -> float:
        if dir.length_squared() < 0.0001:
                return 0.0
        return dir.angle()


## Irregular polygon points (deterministic radii pattern, n verts).
func _rock_pts(r: float, n: int, rot: float, wob: float) -> PackedVector2Array:
        var pts := PackedVector2Array()
        for i in n:
                var a: float = rot + float(i) / float(n) * TAU
                # pseudo-casuale deterministico (seno composto, niente RNG)
                var k: float = 1.0 - wob * (0.5 + 0.5 * sin(float(i) * 2.399 + 1.7))
                pts.append(Vector2(cos(a), sin(a)) * r * k)
        return pts


func _draw_themed(col: Color, radius: float) -> void:
        var t := _t()
        var ang := _dir_angle()
        var r := radius

        match bp_kind:
                BossProjKind.BP_BOULDER:
                        # GOLEM: masso di roccia IRREGOLARE che rotola.
                        var spin := t * 1.2
                        draw_set_transform(Vector2.ZERO, spin)
                        var rock := Color(0.55, 0.45, 0.30).darkened(0.10)
                        var rock_dark := rock.darkened(0.35)
                        var rock_lite := rock.lightened(0.25)
                        draw_colored_polygon(_rock_pts(r, 8, 0.0, 0.30), rock)
                        draw_colored_polygon(_rock_pts(r * 0.72, 8, 0.35, 0.30), rock_lite)
                        # crepe
                        draw_polyline(PackedVector2Array([
                                Vector2(-r * 0.55, -r * 0.2), Vector2(-r * 0.1, r * 0.15),
                                Vector2(r * 0.45, -r * 0.05)]), rock_dark, 1.6, true)
                        draw_polyline(PackedVector2Array([
                                Vector2(-r * 0.25, r * 0.5), Vector2(0.0, r * 0.1)]), rock_dark, 1.2, true)
                        # ombra portata sul lato in basso
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-r * 0.9, r * 0.35), Vector2(0.0, r * 0.95),
                                Vector2(r * 0.85, r * 0.3), Vector2(0.0, r * 0.4)]),
                                Color(0, 0, 0, 0.25))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_NECRO_BOLT:
                        # LICH: teschio necrotico verde luminoso con scia.
                        var pulse := 1.0 + 0.12 * sin(t * 9.0)
                        draw_circle(Vector2.ZERO, r * 2.1 * pulse, Color(col.r, col.g, col.b, 0.16))
                        draw_circle(Vector2.ZERO, r * 1.35, Color(col.r, col.g, col.b, 0.30))
                        # testa (tonda) + mandibola (rettangolo smussato)
                        draw_circle(Vector2.ZERO, r, col)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-r * 0.55, r * 0.35), Vector2(r * 0.55, r * 0.35),
                                Vector2(r * 0.45, r * 0.95), Vector2(-r * 0.45, r * 0.95)]), col)
                        # orbite nere + naso + denti
                        var eye := Color(0.02, 0.08, 0.02)
                        draw_circle(Vector2(-r * 0.38, -r * 0.12), r * 0.26, eye)
                        draw_circle(Vector2(r * 0.38, -r * 0.12), r * 0.26, eye)
                        draw_circle(Vector2(-r * 0.38, -r * 0.12), r * 0.10, Color(0.55, 1.0, 0.6))
                        draw_circle(Vector2(r * 0.38, -r * 0.12), r * 0.10, Color(0.55, 1.0, 0.6))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(0.0, r * 0.18), Vector2(-r * 0.14, r * 0.42),
                                Vector2(r * 0.14, r * 0.42)]), eye)
                        for i in 3:
                                var tx: float = (float(i) - 1.0) * r * 0.28
                                draw_line(Vector2(tx, r * 0.42), Vector2(tx, r * 0.95), eye, 1.4)
                        # scia dietro (direzione opposta al moto)
                        var back := -Vector2(cos(ang), sin(ang))
                        for i in 3:
                                var k := float(i + 1) / 3.0
                                draw_circle(back * r * (1.2 + k * 1.6), r * (0.5 - 0.12 * k),
                                        Color(col.r, col.g, col.b, 0.45 - 0.13 * k))

                BossProjKind.BP_FIREBALL:
                        # DEMON: fiamma a GOCCIA puntata contro la direzione del moto.
                        draw_set_transform(Vector2.ZERO, ang)
                        var sc := 1.4 if variant == 1 else 1.0
                        var rr := r * sc
                        # alone
                        draw_circle(Vector2.ZERO, rr * 1.6, Color(1.0, 0.4, 0.0, 0.28))
                        # fiamma esterna (coda all'indietro)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(rr * 1.1, 0.0),
                                Vector2(rr * 0.1, -rr * 0.85),
                                Vector2(-rr * 1.9 - sin(t * 18.0) * rr * 0.3, -rr * 0.25),
                                Vector2(-rr * 1.5, 0.0),
                                Vector2(-rr * 1.9 + sin(t * 15.0) * rr * 0.3, rr * 0.25),
                                Vector2(rr * 0.1, rr * 0.85)]), Color(1.0, 0.45, 0.10))
                        # fiamma media
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(rr * 0.8, 0.0),
                                Vector2(rr * 0.05, -rr * 0.55),
                                Vector2(-rr * 1.1, 0.0),
                                Vector2(rr * 0.05, rr * 0.55)]), Color(1.0, 0.72, 0.20))
                        # nucleo
                        draw_circle(Vector2(rr * 0.15, 0.0), rr * 0.42, Color(1.0, 0.95, 0.55))
                        # faville
                        for i in 3:
                                var fx := -rr * (1.2 + float(i) * 0.55) - sin(t * 21.0 + float(i)) * rr * 0.2
                                draw_circle(Vector2(fx, sin(t * 13.0 + float(i) * 2.1) * rr * 0.3),
                                        rr * 0.10, Color(1.0, 0.8, 0.3, 0.8))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_WEBSHOT:
                        # SPIDER: disco-RAGNATELA (raggi + anelli) che ruota lento.
                        var spin_w := t * 0.9
                        var web_col := Color(0.92, 0.92, 0.95, 0.95)
                        var web_dim := Color(0.75, 0.75, 0.80, 0.8)
                        draw_circle(Vector2.ZERO, r * 1.15, Color(1.0, 1.0, 1.0, 0.10))
                        # 8 raggi
                        for i in 8:
                                var a: float = spin_w + float(i) * TAU / 8.0
                                draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * r * 1.05,
                                        web_col, 1.3)
                        # 2 anelli concentrici (poligono)
                        for ring in 2:
                                var rr2 := r * (0.45 + 0.55 * float(ring + 1) / 2.0)
                                var pts := PackedVector2Array()
                                for i in 12:
                                        var a2: float = spin_w + float(i) * TAU / 12.0
                                        pts.append(Vector2(cos(a2), sin(a2)) * rr2)
                                draw_polyline(pts, web_dim if ring == 0 else web_col, 1.1, true)
                        # centro appiccicoso
                        draw_circle(Vector2.ZERO, r * 0.16, Color(1.0, 1.0, 1.0, 0.9))
                        draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.08, Color(1.0, 1.0, 1.0, 0.7))

                BossProjKind.BP_FLESH_CHUNK:
                        # ABOMINATION: brandello di CARNE irregolare con macchie.
                        var spin_f := t * 0.8
                        draw_set_transform(Vector2.ZERO, spin_f)
                        var flesh := Color(0.70, 0.45, 0.45)
                        draw_colored_polygon(_rock_pts(r, 9, 0.3, 0.38), flesh)
                        draw_colored_polygon(_rock_pts(r * 0.65, 9, 0.9, 0.38), flesh.lightened(0.18))
                        # macchie scure
                        draw_circle(Vector2(r * 0.25, -r * 0.15), r * 0.16, Color(0.45, 0.18, 0.20))
                        draw_circle(Vector2(-r * 0.3, r * 0.3), r * 0.11, Color(0.45, 0.18, 0.20))
                        # filamento pendente
                        draw_polyline(PackedVector2Array([
                                Vector2(r * 0.8, r * 0.2),
                                Vector2(r * 1.15, r * 0.55 + sin(t * 6.0) * r * 0.1),
                                Vector2(r * 1.05, r * 0.9)]), Color(0.55, 0.30, 0.32), 1.4, true)
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_INK_SPRAY:
                        # KRAKEN: getto d'INCHIOSTRIO (blob + gocce di scia).
                        var ink := Color(0.10, 0.10, 0.30)
                        draw_set_transform(Vector2.ZERO, ang)
                        # blob principale con sbavature
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 1.05, 0.0),
                                Vector2(r * 0.55, -r * 0.9),
                                Vector2(-r * 0.5, -r * 0.75),
                                Vector2(-r * 0.8, 0.0),
                                Vector2(-r * 0.45, r * 0.8),
                                Vector2(r * 0.6, r * 0.85)]), ink)
                        # gocce in scia
                        for i in 3:
                                var k := float(i + 1) / 4.0
                                draw_circle(Vector2(-r * (1.4 + k * 2.0),
                                                sin(t * 7.0 + float(i) * 2.0) * r * 0.4),
                                        r * (0.34 - 0.08 * k), Color(0.10, 0.10, 0.30, 0.85 - 0.22 * k))
                        # riflesso
                        draw_circle(Vector2(r * 0.15, -r * 0.3), r * 0.28, Color(0.42, 0.42, 0.62))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_DRAGON_BREATH:
                        # DRAGON: LINGUA di fiamma allungata (3 strati + braci).
                        draw_set_transform(Vector2.ZERO, ang)
                        var flick := sin(t * 16.0) * 0.15
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 1.9, 0.0),
                                Vector2(r * 0.3, -r * 1.0 * (1.0 + flick)),
                                Vector2(-r * 1.6, -r * 0.45),
                                Vector2(-r * 1.2, 0.0),
                                Vector2(-r * 1.6, r * 0.45),
                                Vector2(r * 0.3, r * 1.0 * (1.0 - flick))]),
                                Color(1.0, 0.30, 0.05, 0.85))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 1.45, 0.0),
                                Vector2(r * 0.25, -r * 0.6),
                                Vector2(-r * 1.0, 0.0),
                                Vector2(r * 0.25, r * 0.6)]), Color(1.0, 0.62, 0.15))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 1.0, 0.0),
                                Vector2(r * 0.2, -r * 0.3),
                                Vector2(-r * 0.55, 0.0),
                                Vector2(r * 0.2, r * 0.3)]), Color(1.0, 0.92, 0.45))
                        for i in 2:
                                draw_circle(Vector2(-r * (1.3 + float(i) * 0.7),
                                                sin(t * 11.0 + float(i) * 3.0) * r * 0.5),
                                        r * 0.09, Color(1.0, 0.5, 0.2, 0.8))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_GHOST_BOLT:
                        # WRAITH: FANTASMA (cupola + orlo ondulato) traslucido.
                        var gh := Color(col.r, col.g, col.b, 0.55)
                        var bob := sin(t * 5.0) * r * 0.12
                        draw_set_transform(Vector2(0.0, bob), 0.0)
                        draw_circle(Vector2.ZERO, r * 1.9, Color(col.r, col.g, col.b, 0.12))
                        var hem := PackedVector2Array()
                        hem.append(Vector2(-r * 0.9, r * 0.25))
                        # cupola
                        for i in 8:
                                var a: float = PI - float(i) * PI / 7.0
                                hem.append(Vector2(cos(a) * r * 0.9, sin(a) * r * 0.9 - r * 0.15))
                        hem.append(Vector2(r * 0.9, r * 0.25))
                        # orlo ondulato (3 lobi)
                        hem.append(Vector2(r * 0.6, r * 0.95 + sin(t * 7.0) * r * 0.10))
                        hem.append(Vector2(r * 0.2, r * 0.45))
                        hem.append(Vector2(-r * 0.2, r * 0.95 + sin(t * 7.0 + 2.0) * r * 0.10))
                        hem.append(Vector2(-r * 0.6, r * 0.45))
                        draw_colored_polygon(hem, gh)
                        # occhi
                        draw_circle(Vector2(-r * 0.32, -r * 0.18), r * 0.15, Color(0.05, 0.15, 0.2, 0.95))
                        draw_circle(Vector2(r * 0.32, -r * 0.18), r * 0.15, Color(0.05, 0.15, 0.2, 0.95))
                        # bocca
                        draw_circle(Vector2(0.0, r * 0.12), r * 0.10, Color(0.05, 0.15, 0.2, 0.9))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_BLOOD_BOLT:
                        # VAMPIRE: dardo-PIPISTRELLO (corpo + ali che sbattono).
                        draw_set_transform(Vector2.ZERO, ang)
                        var flap := sin(t * 11.0) * 0.45
                        var blood := Color(0.70, 0.05, 0.10)
                        # ali (triangoli che oscillano)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 0.2, 0.0),
                                Vector2(-r * 0.4, -r * (1.3 + flap)),
                                Vector2(-r * 0.75, -r * 0.25)]), blood.darkened(0.15))
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 0.2, 0.0),
                                Vector2(-r * 0.4, r * (1.3 - flap)),
                                Vector2(-r * 0.75, r * 0.25)]), blood.darkened(0.15))
                        # corpo (rombo affusolato)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 1.3, 0.0),
                                Vector2(r * 0.1, -r * 0.4),
                                Vector2(-r * 0.8, 0.0),
                                Vector2(r * 0.1, r * 0.4)]), blood)
                        # occhietti + scia di gocce
                        draw_circle(Vector2(r * 0.55, -r * 0.08), r * 0.09, Color(1.0, 0.85, 0.3))
                        draw_circle(Vector2(r * 0.55, r * 0.08), r * 0.09, Color(1.0, 0.85, 0.3))
                        for i in 3:
                                var k := float(i + 1) / 4.0
                                draw_circle(Vector2(-r * (1.2 + k * 1.8), sin(t * 9.0 + float(i)) * r * 0.2),
                                        r * (0.22 - 0.05 * k), Color(0.55, 0.04, 0.08, 0.7 - 0.2 * k))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_EYE_RAY:
                        # BEHOLDER: RAGGIO oculare affusolato con tacche runiche.
                        draw_set_transform(Vector2.ZERO, ang)
                        var beam := col
                        var beam_soft := Color(col.r, col.g, col.b, 0.30)
                        # corpo del raggio: cuneo lungo con punta luminosa
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 2.6, 0.0),
                                Vector2(r * 0.2, -r * 0.55),
                                Vector2(-r * 1.8, -r * 0.9),
                                Vector2(-r * 1.8, r * 0.9),
                                Vector2(r * 0.2, r * 0.55)]), beam_soft)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 2.6, 0.0),
                                Vector2(r * 0.2, -r * 0.32),
                                Vector2(-r * 1.7, 0.0),
                                Vector2(r * 0.2, r * 0.32)]), beam)
                        # tacche runiche lungo il raggio
                        for i in 3:
                                var nx := r * (1.8 - float(i) * 0.9)
                                draw_line(Vector2(nx, -r * 0.22), Vector2(nx, r * 0.22),
                                        Color(1.0, 1.0, 1.0, 0.55), 1.2)
                        # sorgente (occhio) e punta
                        draw_circle(Vector2(-r * 1.6, 0.0), r * 0.75, beam.darkened(0.2))
                        draw_circle(Vector2(-r * 1.6, 0.0), r * 0.4, Color(1.0, 1.0, 1.0, 0.9))
                        draw_circle(Vector2(r * 2.6, 0.0), r * 0.35 + sin(t * 14.0) * r * 0.06,
                                Color(1.0, 1.0, 1.0, 0.95))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_GHOUL_CLAW:
                        # GHOUL: 3 ARTIGLI ricurvi (archi affusolati) su base.
                        draw_set_transform(Vector2.ZERO, ang)
                        var bone := Color(0.85, 0.85, 0.70)
                        var bone_dark := bone.darkened(0.35)
                        # base/osso
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-r * 0.9, 0.0), Vector2(-r * 0.3, -r * 0.45),
                                Vector2(r * 0.3, -r * 0.45), Vector2(r * 0.9, 0.0),
                                Vector2(r * 0.3, r * 0.45), Vector2(-r * 0.3, r * 0.45)]),
                                bone_dark)
                        # 3 artigli ricurvi (falangi che si stringono)
                        for i in 3:
                                var oy: float = (float(i) - 1.0) * r * 0.62
                                var claw := PackedVector2Array()
                                claw.append(Vector2(-r * 0.55, oy + r * 0.28))
                                claw.append(Vector2(r * 0.3 + sin(t * 8.0 + float(i)) * r * 0.08, oy + r * 0.22))
                                claw.append(Vector2(r * 1.35, oy + r * 0.05 * (1.0 if i != 1 else 0.0)))
                                claw.append(Vector2(r * 0.3, oy - r * 0.16))
                                claw.append(Vector2(-r * 0.55, oy - r * 0.28))
                                draw_colored_polygon(claw, bone)
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_SPECTRAL_FANG:
                        # SPECTRAL ALPHA: ZANNA a mezzaluna con scia ectoplasmatica.
                        draw_set_transform(Vector2.ZERO, ang)
                        var fang := Color(0.60, 1.00, 0.70)
                        # mezzaluna (lama curva)
                        var cres := PackedVector2Array()
                        for i in 9:
                                var a: float = -1.15 + float(i) * 1.15 / 4.0
                                cres.append(Vector2(cos(a - PI * 0.5) * r * 1.7 + r * 0.9,
                                                sin(a - PI * 0.5) * r * 1.7))
                        for i in 8:
                                var a2: float = 1.15 - float(i) * 1.15 / 4.0
                                cres.append(Vector2(cos(a2 - PI * 0.5) * r * 0.75 + r * 0.9,
                                                sin(a2 - PI * 0.5) * r * 0.75))
                        draw_colored_polygon(cres, fang)
                        # luccichio sulla punta
                        draw_circle(Vector2(-r * 0.75, 0.0), r * 0.16, Color(1.0, 1.0, 1.0, 0.9))
                        # scia ectoplasmatica
                        for i in 4:
                                var k := float(i + 1) / 5.0
                                draw_circle(Vector2(r * (0.8 + k * 2.2),
                                                sin(t * 10.0 + float(i) * 1.8) * r * 0.35),
                                        r * (0.3 - 0.06 * k), Color(0.6, 1.0, 0.7, 0.5 - 0.11 * k))
                        draw_set_transform(Vector2.ZERO, 0.0)

                BossProjKind.BP_CULT_ORB:
                        # CULT HERALD: orbo con ANELLO-SIGILLO rotante.
                        var pulse_c := 1.0 + 0.10 * sin(t * 8.0)
                        draw_circle(Vector2.ZERO, r * 1.9, Color(col.r, col.g, col.b, 0.18))
                        draw_circle(Vector2.ZERO, r * pulse_c, col)
                        draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.32, Color(1.0, 1.0, 1.0, 0.75))
                        # anello sigillo: 5 tacche radiali che orbitano
                        var rot := t * 2.4
                        draw_arc(Vector2.ZERO, r * 1.45, 0.0, TAU, 24,
                                Color(col.r * 1.2, col.g * 1.2, col.b * 1.3, 0.8), 1.4, true)
                        for i in 5:
                                var a: float = rot + float(i) * TAU / 5.0
                                draw_line(Vector2(cos(a), sin(a)) * r * 1.25,
                                        Vector2(cos(a), sin(a)) * r * 1.65,
                                        Color(1.0, 0.9, 1.0, 0.85), 2.0)
                        # pentagramma interno (linee a stella)
                        for i in 5:
                                var a1: float = rot * 0.5 + float(i) * TAU / 5.0
                                var a2: float = rot * 0.5 + float((i + 2) % 5) * TAU / 5.0
                                draw_line(Vector2(cos(a1), sin(a1)) * r * 0.8,
                                        Vector2(cos(a2), sin(a2)) * r * 0.8,
                                        Color(1.0, 0.85, 1.0, 0.55), 1.0)

                BossProjKind.BP_MIMIC_GOO:
                        # COLOSSAL MIMIC: MELMA con tentaglioli gocciolanti.
                        var goo := Color(0.40, 0.80, 0.20)
                        var goo_dark := goo.darkened(0.3)
                        var drip := sin(t * 6.0)
                        draw_circle(Vector2.ZERO, r * 1.25, Color(0.25, 0.55, 0.12, 0.35))
                        # blob principale (ellisse schiacciata + onda)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-r * 1.1, -r * 0.35), Vector2(-r * 0.4, -r * 0.85),
                                Vector2(r * 0.5, -r * 0.8), Vector2(r * 1.15, -r * 0.2),
                                Vector2(r * 0.9, r * 0.5), Vector2(r * 0.1, r * 0.75 + drip * r * 0.1),
                                Vector2(-r * 0.7, r * 0.55)]), goo)
                        # tentaglioli che gocciolano
                        draw_polyline(PackedVector2Array([
                                Vector2(-r * 0.5, r * 0.5), Vector2(-r * 0.6, r * 1.0),
                                Vector2(-r * 0.45, r * 1.45)]), goo_dark, r * 0.28, true)
                        draw_polyline(PackedVector2Array([
                                Vector2(r * 0.55, r * 0.45), Vector2(r * 0.7, r * 0.9)]), goo_dark, r * 0.22, true)
                        # gocce staccate
                        draw_circle(Vector2(-r * 0.45, r * 1.75 + drip * r * 0.15), r * 0.14, goo_dark)
                        # riflesso viscido
                        draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.26, Color(0.7, 1.0, 0.4))
                        # bollicine
                        draw_circle(Vector2(r * 0.35, -r * 0.2), r * 0.10, Color(0.75, 1.0, 0.5, 0.8))
                        draw_circle(Vector2(r * 0.05, r * 0.2), r * 0.07, Color(0.75, 1.0, 0.5, 0.6))

                BossProjKind.BP_RAT_SWARM:
                        # RAT KING: 3 TOPINI che corrono (corpo + orecchie + coda).
                        for i in 3:
                                var phase := t * 12.0 + float(i) * 2.1
                                var hop := absf(sin(phase)) * r * 0.35
                                var ox := (float(i) - 1.0) * r * 0.9
                                var oy := -hop + float(i - 1) * r * 0.18
                                var fur := Color(0.30, 0.25, 0.20).lightened(0.05 * float(i))
                                # coda serpentina
                                draw_polyline(PackedVector2Array([
                                        Vector2(ox + r * 0.55, oy),
                                        Vector2(ox + r * 0.85, oy - r * 0.25 + sin(phase) * r * 0.2),
                                        Vector2(ox + r * 1.15, oy - r * 0.1 + cos(phase) * r * 0.15)]),
                                        Color(0.55, 0.45, 0.38), 1.2, true)
                                # corpo (ellisse)
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(ox - r * 0.5, oy), Vector2(ox - r * 0.25, oy - r * 0.32),
                                        Vector2(ox + r * 0.3, oy - r * 0.28), Vector2(ox + r * 0.55, oy),
                                        Vector2(ox + r * 0.3, oy + r * 0.28), Vector2(ox - r * 0.25, oy + r * 0.3)]),
                                        fur)
                                # orecchie
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(ox - r * 0.3, oy - r * 0.25),
                                        Vector2(ox - r * 0.2, oy - r * 0.55),
                                        Vector2(ox - r * 0.08, oy - r * 0.28)]), fur.darkened(0.2))
                                # occhietto
                                draw_circle(Vector2(ox - r * 0.32, oy - r * 0.05), r * 0.07, Color(1.0, 0.35, 0.2))

                BossProjKind.BP_WITCH_HEX:
                        # SUPREME WITCH: SFERA DI CRISTALLO sfaccettata + bagliori.
                        var gem := Color(0.85, 0.20, 0.85)
                        var gem_lite := gem.lightened(0.35)
                        var gem_dark := gem.darkened(0.35)
                        draw_circle(Vector2.ZERO, r * 1.9, Color(gem.r, gem.g, gem.b, 0.15))
                        # gemma esagonale
                        var hex := PackedVector2Array()
                        for i in 6:
                                var a: float = float(i) * TAU / 6.0
                                hex.append(Vector2(cos(a), sin(a)) * r * 1.05)
                        draw_colored_polygon(hex, gem)
                        # sfaccettature (triangoli interni alternati)
                        for i in 3:
                                var a1: float = float(i * 2) * TAU / 6.0
                                var a2: float = float(i * 2 + 1) * TAU / 6.0
                                var a3: float = float(i * 2 + 2) * TAU / 6.0
                                draw_colored_polygon(PackedVector2Array([
                                        Vector2(cos(a1), sin(a1)) * r * 1.05,
                                        Vector2(cos(a2), sin(a2)) * r * 1.05,
                                        Vector2(cos(a3), sin(a3)) * r * 1.05]), gem_dark)
                        # nucleo luminoso + croce interna (esempio: globo della strega)
                        draw_circle(Vector2.ZERO, r * 0.42, gem_lite)
                        draw_line(Vector2(-r * 0.55, 0.0), Vector2(r * 0.55, 0.0),
                                Color(1.0, 0.6, 1.0, 0.9), 1.0)
                        draw_line(Vector2(0.0, -r * 0.55), Vector2(0.0, r * 0.55),
                                Color(1.0, 0.6, 1.0, 0.9), 1.0)
                        # bagliori orbitanti (due glinti su orbite opposte)
                        for i in 2:
                                var a: float = t * 3.2 + float(i) * PI
                                draw_circle(Vector2(cos(a), sin(a)) * r * 1.25, r * 0.12,
                                        Color(1.0, 0.9, 1.0, 0.9))
                        # alone esagonale sottile
                        draw_polyline(hex, Color(1.0, 0.75, 1.0, 0.5), 1.0, true)

                BossProjKind.BP_TWILIGHT_BLADE:
                        # TWILIGHT KNIGHT: PUGNALE ombroso che ruota su sé stesso.
                        var spin_b := t * 2.0
                        draw_set_transform(Vector2.ZERO, spin_b)
                        var steel := Color(0.20, 0.10, 0.30)
                        var edge := Color(0.55, 0.40, 0.75)
                        # alone
                        draw_circle(Vector2.ZERO, r * 1.5, Color(0.3, 0.15, 0.45, 0.20))
                        # lama (lungo +X, punta avanti)
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(r * 2.1, 0.0),
                                Vector2(r * 0.3, -r * 0.32),
                                Vector2(-r * 0.5, -r * 0.22),
                                Vector2(-r * 0.5, r * 0.22),
                                Vector2(r * 0.3, r * 0.32)]), steel)
                        # filo luminoso
                        draw_line(Vector2(r * 2.1, 0.0), Vector2(-r * 0.5, 0.0), edge, 1.0)
                        # guardia
                        draw_colored_polygon(PackedVector2Array([
                                Vector2(-r * 0.5, -r * 0.7), Vector2(-r * 0.68, -r * 0.55),
                                Vector2(-r * 0.68, r * 0.55), Vector2(-r * 0.5, r * 0.7),
                                Vector2(-r * 0.42, 0.0)]), Color(0.45, 0.35, 0.60))
                        # impugnatura + pomo
                        draw_rect(Rect2(-r * 1.15, -r * 0.12, r * 0.5, r * 0.24), Color(0.12, 0.08, 0.18))
                        draw_circle(Vector2(-r * 1.25, 0.0), r * 0.2, Color(0.6, 0.5, 0.8))
                        draw_set_transform(Vector2.ZERO, 0.0)

                _:
                        # Fallback identico al legacy per sicurezza.
                        draw_circle(Vector2.ZERO, radius, col)


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

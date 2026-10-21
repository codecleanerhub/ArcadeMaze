## BossSiegeCannon.gd — TASK 39 (L'Arena del Boss).
##
## CANNONE D'ASSEDIO: pickup d'arma ESCLUSIVO della stanza del boss (non
## esiste nel labirinto, non entra nel pool delle armi a terra casuali).
## Raccoglierlo equipaggia l'arma SIEGE: 4 palle di cannone pesanti che
## infliggono danni ingenti al boss (potenza flat + %HP massimi).
##
## GRAFICA: cannone in bronzo su affusto di legno, pre-renderizzato per-pixel
## (canna con evidenziazione cilindrica e bocca fumante, anelli dorati,
## ruote a raggi, miccia a spirale) + bagliore dorato pulsante live e
## scintille che salgono dalla miccia.
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

const TEX_W: int = 56
const TEX_H: int = 44
const PICKUP_RADIUS_SQ: float = 900.0   # 30 px

var _t: float = 0.0
var _seed: float = 0.0
var _tex: ImageTexture = null
static var _tex_cache: ImageTexture = null


func setup(spawn_pos: Vector2) -> void:
        position = spawn_pos


func _ready() -> void:
        z_index = 15
        process_mode = Node.PROCESS_MODE_PAUSABLE
        add_to_group("arena_siege")
        _seed = randf() * 100.0
        _tex = make_cannon_texture()


func _process(delta: float) -> void:
        _t += delta
        queue_redraw()


func _draw() -> void:
        var bob: float = sin(_t * 2.0 + _seed) * 2.5
        # aura dorata pulsante (richiama le armi a terra ma piu' maestosa)
        var pulse: float = 0.6 + 0.4 * sin(_t * 3.4 + _seed)
        for i in 3:
                draw_circle(Vector2(0.0, 8.0), 34.0 - float(i) * 8.0,
                                Color(1.0, 0.80, 0.30, 0.09 * pulse))
        if _tex != null:
                draw_set_transform(Vector2(0.0, bob), 0.0, Vector2.ONE)
                draw_texture(_tex, Vector2(-TEX_W * 0.5, -TEX_H * 0.5))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # scintille che salgono dalla miccia
        for k in 3:
                var st: float = fmod(_t * 0.55 + float(k) * 0.33 + _seed * 0.1, 1.0)
                draw_circle(Vector2(TEX_W * 0.5 - 8.0 + sin(_t * 2.6 + float(k) * 2.1) * 3.0,
                                bob - TEX_H * 0.5 - 4.0 - st * 16.0),
                                1.4 * (1.0 - st) + 0.5,
                                Color(1.0, 0.85, 0.35, 0.65 * (1.0 - st)))
        # riflesso dorato sulla canna (live, sopra la texture)
        draw_circle(Vector2(-6.0, bob - 6.0), 2.2,
                        Color(1.0, 0.90, 0.50, 0.35 + 0.25 * pulse))


## Il controller costruisce l'arma quando il player passa sopra il pickup.
static func make_siege_weapon() -> Dictionary:
        return {
                "type": C.WeaponType.SIEGE,
                "power": C.BOSS_ARENA_SIEGE_POWER,
                "ammo": C.BOSS_ARENA_SIEGE_AMMO,
                "max_ammo": C.BOSS_ARENA_SIEGE_AMMO,
                "siege": true,
        }


# ============================================================================
# Texture procedurale: cannone in bronzo su affusto, per-pixel
# ============================================================================

## Canna in bronzo (ciclindro orizzontale verso destra) con bocca scura e
## anelli dorati, affusto in legno a trapezio, ruota a 4 raggi con cerchione,
## miccia a spirale dietro.
static func make_cannon_texture() -> ImageTexture:
        if _tex_cache != null:
                return _tex_cache
        var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
        var barrel_top: int = 8
        var barrel_bot: int = 26
        var barrel_l: int = 6
        var barrel_r: int = 48
        var cy: float = (float(barrel_top) + float(barrel_bot)) * 0.5

        for y in TEX_H:
                for x in TEX_W:
                        var col := Color(0, 0, 0, 0)
                        # --- canna ---
                        if x >= barrel_l and x < barrel_r and y >= barrel_top and y < barrel_bot:
                                var u: float = (float(y) - barrel_top) \
                                                / float(barrel_bot - barrel_top)
                                var cyl: float = 0.55 + 0.45 * sin(PI * u)
                                # leggero rastremarsi verso la bocca
                                var taper: float = 0.88 + 0.12 * (1.0
                                                - float(x - barrel_l)
                                                / float(barrel_r - barrel_l))
                                var bronze: float = cyl * taper
                                col = Color(0.48 * bronze + 0.05, 0.34 * bronze + 0.04,
                                                0.20 * bronze + 0.03, 1.0)
                                # banda di rafforzamento + anelli dorati
                                var rel_x: float = float(x - barrel_l) / float(barrel_r - barrel_l)
                                if rel_x < 0.10 or (rel_x > 0.42 and rel_x < 0.50):
                                        col = Color(0.62 * cyl + 0.10, 0.50 * cyl + 0.08,
                                                        0.24 * cyl + 0.05, 1.0)  # bronzo carico
                                if absf(rel_x - 0.26) < 0.030 or absf(rel_x - 0.70) < 0.030:
                                        col = Color(0.95 * cyl + 0.05, 0.78 * cyl + 0.06,
                                                        0.30 * cyl + 0.04, 1.0)  # oro
                                # bocca della canna (apertura scura)
                                if x >= barrel_r - 5:
                                        var mouth_u: float = (float(x) - (barrel_r - 5)) / 5.0
                                        col = col.lerp(Color(0.07, 0.05, 0.04), mouth_u * 0.9)
                                # riflesso lungo il bordo superiore
                                if y == barrel_top + 1 or y == barrel_top + 2:
                                        col = col.lightened(0.30)
                                if y == barrel_bot - 1:
                                        col = col.darkened(0.30)
                        # --- affusto di legno (trapezio sotto la canna) ---
                        elif x >= 10 and x < 46 and y >= barrel_bot and y < 40:
                                var taper_x: float = float(y - barrel_bot) / 14.0
                                var in_l: float = 12.0 + taper_x * 6.0
                                var in_r: float = 44.0 - taper_x * 6.0
                                if float(x) >= in_l and float(x) < in_r:
                                        var u2: float = (float(x) - in_l) / (in_r - in_l)
                                        var wood_sh: float = 0.60 + 0.40 * sin(PI * u2)
                                        col = Color(0.34 * wood_sh, 0.22 * wood_sh,
                                                        0.12 * wood_sh, 1.0)
                                        # viva del legno
                                        if fmod(float(y) * 1.3 + float(x) * 0.7, 7.0) < 0.9:
                                                col = col.darkened(0.22)
                        # --- ruota posteriore (a raggi, con cerchione) ---
                        elif y >= 24 and y < 44 and x >= 4 and x < 24:
                                var wx: float = float(x) - 13.0
                                var wy: float = float(y) - 33.0
                                var dist: float = sqrt(wx * wx + wy * wy)
                                if dist <= 9.0:
                                        var ang: float = atan2(wy, wx)
                                        col = Color(0.30, 0.19, 0.10, 1.0)  # legno ruota
                                        # cerchione ferro
                                        if dist > 7.0:
                                                col = Color(0.34, 0.33, 0.36, 1.0)
                                        # 4 raggi
                                        var spoke: float = absf(sin(ang * 2.0))
                                        if spoke > 0.90 and dist <= 7.0:
                                                col = Color(0.42, 0.28, 0.15, 1.0)
                                        # mozzo centrale dorato
                                        if dist < 2.2:
                                                col = Color(0.85, 0.68, 0.28, 1.0)
                        # --- miccia a spirale dietro (piccoli punti) ---
                        elif x >= 46 and x < 54 and y >= 6 and y < 14:
                                var fx: float = float(x) - 47.0
                                var fy: float = float(y) - 7.0
                                var fd: float = sqrt(fx * fx + fy * fy)
                                var fa: float = atan2(fy, fx)
                                # spirale di archimede r = 1.2 + 0.55*theta
                                var r_spir: float = 1.0 + 0.52 * (fa + PI / 2.0)
                                if absf(fd - r_spir) < 1.1:
                                        col = Color(0.72, 0.55, 0.25, 1.0)
                        img.set_pixel(x, y, col)

        # ombra a terra sotto il cannone
        for x in range(8, 50):
                var a: float = 0.30 * sin(PI * float(x - 8) / 42.0)
                img.set_pixel(x, 41, Color(0, 0, 0, a))
                img.set_pixel(x, 42, Color(0, 0, 0, a * 0.6))

        var tex := ImageTexture.create_from_image(img)
        _tex_cache = tex
        return tex

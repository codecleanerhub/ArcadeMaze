## ElementalBarrel.gd — TASK 39 (L'Arena del Boss).
##
## BARILE ELEMENTALE raccoglibile e lanciabile dal player nella stanza del
## boss. Quattro elementi (FUOCO/GHIACCIO/FULMINE/VELENO) con detonazione
## dedicata; l'elemento DEBOLE del boss infligge il 250% del danno.
##
## Stati:
##   IDLE    — a terra: bob leggero, bagliore elementale pulsante, scintille
##   CARRIED — fluttua sopra la testa del portatore (segue con lieve ritardo);
##             se il portatore muore/svanisce ricade a terra (self-healing)
##   THROWN  — fisica: velocita' + attrito, rotazione, rimbalzi sui bordi
##             stanza, miccia che scintilla; esplode sul boss, dopo 3 rimbalzi
##             o a fine miccia
##   EXPLODING — deflagrazione elementale (~650ms): core bianco -> colore
##             elemento, 5 onde d'urto, spine radiali, fumo, detriti e (se
##             debolezza) testo "DEBOLEZZA!" ascendente; poi autodistruzione
##
## GRAFICA: il corpo del barile e' una TEXTURE PROCEDURALE pre-renderizzata
## per pixel (doghe di legno con venatura e ombreggiatura cilindrica, cerchi
## di ferro con rivetti, coperchio ellittico, runa elementale incisa) — la
## parte animata (bagliore, scintille, esplosione) e' disegnata live sopra.
##
## Pattern LightningStrikeEffect: PROCESS_MODE_PAUSABLE, z_index 15 (sopra il
## pavimento e gli effetti stanza, sotto fulmini/pergamene e HUD).
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")

signal exploded(pos: Vector2, element: int)

enum State { IDLE, CARRIED, THROWN, EXPLODING }

const TEX_W: int = 48
const TEX_H: int = 60
const PICKUP_RADIUS_SQ: float = 676.0        # 26 px
const CARRY_OFFSET: Vector2 = Vector2(0.0, -34.0)
const CARRY_LERP: float = 0.35
const THROW_SPEED: float = 7.5
const THROW_FRICTION: float = 0.986
const FUSE_MS: float = 2400.0
const MAX_BOUNCES: int = 3
const EXPLOSION_MS: float = 650.0

var element: int = C.ElementKind.FIRE
var state: int = State.IDLE
var carrier: CharacterBody2D = null
var velocity: Vector2 = Vector2.ZERO
var spin_deg: float = 0.0
var spin_vel_deg: float = 0.0
var fuse_ms: float = 0.0
var bounces: int = 0
var _life_ms: float = 0.0
var _t: float = 0.0
var _rng_seed: float = 0.0
var _weak_hit: bool = false
var _pal: Dictionary = {}
var _tex: ImageTexture = null

# Cache delle texture per elemento (generata alla prima richiesta).
static var _tex_cache: Dictionary = {}


## `spawn_pos`: coordinate MONDO. `el`: C.ElementKind.*
func setup(spawn_pos: Vector2, el: int) -> void:
        position = spawn_pos
        element = el
        _pal = C.get_element_palette(el)
        _tex = make_barrel_texture(el)


func _ready() -> void:
        z_index = 15
        process_mode = Node.PROCESS_MODE_PAUSABLE
        add_to_group("arena_barrels")
        _rng_seed = randf() * 100.0
        if _tex == null:
                _tex = make_barrel_texture(element)


func _process(delta: float) -> void:
        _t += delta
        match state:
                State.IDLE:
                        _life_ms += delta * 1000.0
                State.CARRIED:
                        _update_carried(delta)
                State.THROWN:
                        _update_thrown(delta)
                State.EXPLODING:
                        _life_ms -= delta * 1000.0
                        if _life_ms <= 0.0:
                                queue_free()
                                return
        queue_redraw()


# Il portatore e' ancora valido? (morte, eliminazione, anima in transito)
func _carrier_alive() -> bool:
        return carrier != null and is_instance_valid(carrier) \
                        and carrier.visible and carrier.lives > 0 \
                        and not carrier.soul_pending


func _update_carried(_delta: float) -> void:
        if not _carrier_alive():
                drop()
                return
        var target: Vector2 = carrier.position + CARRY_OFFSET
        position = position.lerp(target, CARRY_LERP)


func _update_thrown(delta: float) -> void:
        var step: float = delta * 60.0
        position += velocity * step
        spin_deg += spin_vel_deg * step
        velocity *= pow(THROW_FRICTION, step)
        # Rimbalzi sui bordi della stanza (UI in alto).
        var margin: float = 26.0
        var bounced: bool = false
        if position.x < margin:
                position.x = margin
                velocity.x = absf(velocity.x) * 0.82
                bounced = true
        elif position.x > float(C.WINDOW_WIDTH) - margin:
                position.x = float(C.WINDOW_WIDTH) - margin
                velocity.x = -absf(velocity.x) * 0.82
                bounced = true
        if position.y < float(C.UI_HEIGHT) + margin:
                position.y = float(C.UI_HEIGHT) + margin
                velocity.y = absf(velocity.y) * 0.82
                bounced = true
        elif position.y > float(C.WINDOW_HEIGHT) - margin:
                position.y = float(C.WINDOW_HEIGHT) - margin
                velocity.y = -absf(velocity.y) * 0.82
                bounced = true
        if bounced:
                bounces += 1
                spin_vel_deg *= -0.7
                if bounces >= MAX_BOUNCES:
                        detonate()
                        return
        fuse_ms -= delta * 1000.0
        if fuse_ms <= 0.0:
                detonate()


## Raccoglie il barile (chiamato dal controller sul contatto col player).
func pickup(by_player: CharacterBody2D) -> bool:
        if state != State.IDLE:
                return false
        carrier = by_player
        state = State.CARRIED
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.WEAPON_PICKUP)
        return true


## Lascia cadere il barile dove si trova (morte del portatore, fine fight).
func drop() -> void:
        carrier = null
        state = State.IDLE
        velocity = Vector2.ZERO
        spin_deg = 0.0
        spin_vel_deg = 0.0
        fuse_ms = 0.0
        bounces = 0


## Lancia il barile nella direzione di mira del portatore (tasto di fuoco).
func throw_barrel(dir: Vector2) -> void:
        if state != State.CARRIED or not _carrier_alive():
                return
        if dir == Vector2.ZERO:
                dir = Vector2(1.0, 0.0)
        position = carrier.position + dir * 22.0 + Vector2(0.0, -18.0)
        velocity = dir.normalized() * THROW_SPEED
        spin_vel_deg = 14.0 * (1.0 if dir.x >= 0.0 else -1.0)
        carrier = null
        state = State.THROWN
        fuse_ms = FUSE_MS
        bounces = 0
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.BARREL_TOSS)


## Detonazione: emette il segnale (il controller applica i danni a boss e
## player) e impersona la deflagrazione elementale.
func detonate() -> void:
        if state == State.EXPLODING:
                return
        state = State.EXPLODING
        carrier = null
        _life_ms = EXPLOSION_MS
        exploded.emit(position, element)


## Il controller lo chiama quando l'elemento era la DEBOLEZZA del boss:
## mostra il testo critico ascendente durante l'esplosione.
func confirm_weakness() -> void:
        _weak_hit = true


func is_idle() -> bool:
        return state == State.IDLE


func is_carried_by(p: CharacterBody2D) -> bool:
        return state == State.CARRIED and carrier == p


# ============================================================================
# Rendering
# ============================================================================

func _draw() -> void:
        match state:
                State.IDLE, State.CARRIED, State.THROWN:
                        _draw_body()
                State.EXPLODING:
                        _draw_explosion()


func _draw_body() -> void:
        var bob: float = 0.0
        var glow: float = 1.0
        match state:
                State.IDLE:
                        bob = sin(_t * 2.2 + _rng_seed) * 2.5
                        glow = 0.75 + 0.25 * sin(_t * 3.1 + _rng_seed)
                State.CARRIED:
                        bob = sin(_t * 5.0) * 1.5
                        glow = 0.95 + 0.05 * sin(_t * 8.0)
                State.THROWN:
                        glow = 1.0
        var col: Color = _pal.get("color", Color.WHITE)
        var glow_col: Color = _pal.get("glow", Color.WHITE)

        # 1) alone elementale a terra / sul portatore
        if state != State.THROWN:
                for i in 3:
                        draw_circle(Vector2(0.0, TEX_H * 0.5 - 4.0),
                                        26.0 - float(i) * 7.0,
                                        Color(glow_col.r, glow_col.g, glow_col.b,
                                                        0.10 * glow))
        # 2) corpo del barile (texture pre-renderizzata) con bob/rotazione
        if _tex != null:
                draw_set_transform(Vector2(0.0, bob),
                                deg_to_rad(spin_deg if state == State.THROWN else 0.0),
                                Vector2.ONE)
                draw_texture(_tex, Vector2(-TEX_W * 0.5, -TEX_H * 0.5))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # 3) bagliore vivo della runa (sopra la texture)
        var rune_pulse: float = 0.55 + 0.45 * sin(_t * 4.4 + _rng_seed)
        var cy: float = bob + 2.0
        draw_circle(Vector2(0.0, cy), 11.0,
                        Color(col.r, col.g, col.b, 0.20 * rune_pulse * glow))
        draw_circle(Vector2(0.0, cy), 6.5,
                        Color(col.r, col.g, col.b, 0.34 * rune_pulse * glow))
        # 4) miccia scintillante quando vola
        if state == State.THROWN:
                for k in 4:
                        var ang: float = _t * 21.0 + float(k) * TAU * 0.25
                        var rr: float = 16.0 + 5.0 * sin(_t * 17.0 + float(k))
                        draw_circle(Vector2(cos(ang) * rr * 0.6,
                                        cy - 22.0 + sin(ang) * rr * 0.35),
                                        1.6 + float(k == 0) * 0.9,
                                        Color(1.0, 0.93, 0.55,
                                                        0.55 + 0.35 * sin(_t * 31.0 + float(k))))
                # strisci di movimento
                var dirv: Vector2 = velocity.normalized() \
                                if velocity.length() > 0.1 else Vector2.RIGHT
                for k in 3:
                        draw_circle(-dirv * (12.0 + float(k) * 9.0) + Vector2(0.0, bob),
                                        4.0 - float(k) * 1.0,
                                        Color(col.r, col.g, col.b, 0.16 - float(k) * 0.04))
        # 5) mini-scintille ambientali da fermo
        elif state == State.IDLE:
                for k in 3:
                        var st: float = fmod(_t * 0.6 + float(k) * 0.37 + _rng_seed * 0.1, 1.0)
                        draw_circle(Vector2(sin(_t * 1.7 + float(k) * 2.6) * 16.0,
                                        cy + 4.0 - st * 30.0),
                                        1.3 * (1.0 - st) + 0.4,
                                        Color(glow_col.r, glow_col.g, glow_col.b,
                                                        0.55 * (1.0 - st)))


# Deflagrazione elementale: alone ambientale, core bianco->colore, DOPPIA
# onda d'urto (anelli elementali + traccia bianca), spine coniche ruotanti,
# fumo, detriti e testo DEBOLEZZA se critico.
func _draw_explosion() -> void:
        var k: float = 1.0 - clampf(_life_ms / EXPLOSION_MS, 0.0, 1.0)  # 0->1
        var col: Color = _pal.get("color", Color.WHITE)
        var glow: Color = _pal.get("glow", Color.WHITE)
        var fade: float = 1.0 - k
        # 1) alone ambientale largo (la stanza si tinge dell'elemento)
        draw_circle(Vector2.ZERO, 130.0 * k + 34.0,
                        Color(glow.r, glow.g, glow.b, 0.10 * (1.0 - k)))
        draw_circle(Vector2.ZERO, 80.0 * k + 22.0,
                        Color(glow.r, glow.g, glow.b, 0.14 * (1.0 - k)))
        # 2) core incandescente (collassa mentre l'onda si espande)
        var core_r: float = (1.0 - k) * 40.0 + 8.0
        draw_circle(Vector2.ZERO, core_r + 12.0 * fade,
                        Color(glow.r, glow.g, glow.b, 0.30 * fade))
        draw_circle(Vector2.ZERO, core_r * 0.95,
                        Color(col.r, col.g, col.b, 0.90 * fade))
        draw_circle(Vector2.ZERO, core_r * 0.62,
                        Color(1.0, 0.98, 0.90, 0.97 * fade))
        draw_circle(Vector2.ZERO, core_r * 0.30,
                        Color(1.0, 1.0, 1.0, 0.98 * fade))
        # 3) DOPPIA onda d'urto: 5 anelli elementali + traccia bianca interna
        for ring in 5:
                var rk: float = clampf(k * 1.45 - float(ring) * 0.11, 0.0, 1.0)
                if rk <= 0.0:
                        continue
                var rr: float = 22.0 + rk * (92.0 + float(ring) * 10.0)
                draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48,
                                Color(glow.r, glow.g, glow.b,
                                                0.70 * (1.0 - rk)), 4.6 - float(ring) * 0.5)
                if ring < 4:
                        draw_arc(Vector2.ZERO, rr - 7.0, 0.0, TAU, 48,
                                        Color(1.0, 1.0, 0.92,
                                                        0.35 * (1.0 - rk)), 1.8)
        # 4) spine coniche ruotanti (frammenti incandescenti)
        var spikes: int = 12
        for sidx in spikes:
                var ang: float = TAU * float(sidx) / float(spikes) \
                                + k * 2.4 + _rng_seed
                var len: float = (30.0 + 62.0 * k) \
                                * (0.62 + 0.38 * sin(_rng_seed + float(sidx) * 2.3))
                var half_a: float = (0.16 + 0.10 * (1.0 - k)) * (1.0 - k * 0.45)
                var tip: Vector2 = Vector2(cos(ang), sin(ang)) * len
                var base_l: Vector2 = Vector2(cos(ang - half_a), sin(ang - half_a)) \
                                * core_r * 0.8
                var base_r: Vector2 = Vector2(cos(ang + half_a), sin(ang + half_a)) \
                                * core_r * 0.8
                # spina: triangolo pieno elementale + punta bianco-calda
                draw_colored_polygon(PackedVector2Array([base_l, tip, base_r]),
                                Color(col.r, col.g, col.b, 0.72 * fade))
                var tip_inner: Vector2 = Vector2(cos(ang), sin(ang)) \
                                * (len * 0.78 + core_r * 0.22)
                draw_colored_polygon(PackedVector2Array([
                                base_l * 0.5, tip_inner, base_r * 0.5]),
                                Color(1.0, 0.95, 0.80, 0.55 * fade))
        # 5) fumo che sale + detriti che ricadono
        for d_idx in 6:
                var d_ang: float = TAU * float(d_idx) / 6.0 + _rng_seed
                var d_k: float = clampf(k * 1.3 - float(d_idx) * 0.05, 0.0, 1.0)
                if d_k <= 0.0:
                        continue
                var d_pos: Vector2 = Vector2(cos(d_ang), sin(d_ang) * 0.7) \
                                * (18.0 + 62.0 * d_k) + Vector2(0.0, -16.0 * d_k)
                draw_circle(d_pos, 3.4 * (1.0 - d_k) + 1.2,
                                Color(0.22, 0.20, 0.19, 0.55 * (1.0 - d_k)))
        # 6) testo DEBOLEZZA! (critico elementale)
        if _weak_hit:
                var rise: float = k * 46.0
                var font: Font = ThemeDB.fallback_font
                var txt: String = "DEBOLEZZA!"
                var txt_pos: Vector2 = Vector2(-44.0, -52.0 - rise)
                draw_string(font, txt_pos + Vector2(1.5, 1.5), txt,
                                HORIZONTAL_ALIGNMENT_LEFT, 90.0, 17,
                                Color(0.05, 0.02, 0.0, 0.85 * fade))
                draw_string(font, txt_pos, txt,
                                HORIZONTAL_ALIGNMENT_LEFT, 90.0, 17,
                                Color(1.0, 0.55 + 0.4 * sin(_t * 21.0), 0.25,
                                                clampf(fade * 1.6, 0.0, 1.0)))


# ============================================================================
# Texture procedurale (corpo del barile) — generata per-pixel, cache per elemento
# ============================================================================

## Barile di legno 48x60: doghe verticali con venatura (rumore deterministico
## via hash), ombreggiatura cilindrica (scuro ai bordi, luce a 1/3), due
## cerchi di ferro con rivetti, coperchio ellittico, runa elementale incisa
## sul fronte (glifo per elemento) e contorno scuro.
static func make_barrel_texture(el: int) -> ImageTexture:
        if _tex_cache.has(el):
                return _tex_cache[el]
        var pal: Dictionary = C.get_element_palette(el)
        var wood: Color = pal.get("wood", Color(0.35, 0.22, 0.11))
        var rune: Color = pal.get("color", Color.WHITE)

        var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
        var body_l: int = 5              # margine sinistro corpo
        var body_r: int = TEX_W - 5      # margine destro
        var body_t: int = 7              # inizio corpo (sotto il coperchio)
        var body_b: int = TEX_H - 4      # fondo
        var cx: float = (float(body_l) + float(body_r)) * 0.5

        for y in TEX_H:
                for x in TEX_W:
                        var col := Color(0, 0, 0, 0)
                        var in_body: bool = x >= body_l and x < body_r \
                                        and y >= body_t and y < body_b
                        if in_body:
                                var u: float = (float(x) - body_l) / float(body_r - body_l)
                                # ombreggiatura cilindrica + doghe larghe 8px
                                var cyl: float = 0.52 + 0.48 * sin(PI * u)
                                var stave: float = 1.0
                                var stave_x: int = (x - body_l) % 8
                                if stave_x == 0:
                                        stave = 0.55           # giuntura scura
                                elif stave_x == 1:
                                        stave = 1.16           # filo illuminato
                                # venatura del legno (righe orizzontali ondulate)
                                var grain: float = 1.0 + 0.07 * sin(float(y) * 1.7
                                                + _hash2(x * 7 + el * 131, y * 13) * 2.2)
                                # rigonfiamento dei cerchi (leggera botte)
                                var bulge: float = 1.0 + 0.05 * sin(PI * clampf(
                                                (float(y) - body_t)
                                                / float(body_b - body_t), 0.0, 1.0))
                                var shade: float = cyl * stave * grain * bulge
                                col = Color(wood.r * shade, wood.g * shade,
                                                wood.b * shade, 1.0)
                                # bande di ferro (y 14..20 e 40..46)
                                if (y >= 14 and y <= 20) or (y >= 40 and y <= 46):
                                        var band_u: float = u
                                        var metal: float = 0.62 + 0.38 * sin(PI * band_u)
                                        col = Color(0.30 * metal + 0.04,
                                                        0.29 * metal + 0.04,
                                                        0.33 * metal + 0.05, 1.0)
                                        # riflettitura orizzontale della banda
                                        if y == 14 or y == 40:
                                                col = col.lightened(0.35)
                                        if y == 20 or y == 46:
                                                col = col.darkened(0.30)
                                        # rivetti ogni 8 px
                                        if (x - body_l) % 8 == 4 and (y == 17 or y == 43):
                                                col = Color(0.88, 0.86, 0.80)
                                # contorno verticale dei fianchi
                                if x == body_l or x == body_r - 1:
                                        col = col.darkened(0.45)
                        elif y >= 2 and y < body_t and x >= body_l - 1 and x < body_r + 1:
                                # coperchio ellittico
                                var ex: float = (float(x) - cx) / float(body_r - cx + 1.0)
                                var ey: float = (float(y) - 2.0) / float(body_t - 2.0)
                                if ex * ex + ey * ey <= 1.0:
                                        var lid_shade: float = 0.85 - 0.25 * ey
                                        if ex * ex + ey * ey > 0.72:
                                                col = Color(wood.r * 0.62, wood.g * 0.62,
                                                                wood.b * 0.62, 1.0)  # bordo
                                        else:
                                                col = Color(wood.r * lid_shade * 1.1,
                                                                wood.g * lid_shade * 1.1,
                                                                wood.b * lid_shade * 1.1, 1.0)
                                                # traversa del coperchio
                                                if absf(float(x) - cx) < 2.0:
                                                        col = col.darkened(0.28)
                        elif y == body_b or (y > body_b and y < TEX_H - 1) \
                                        and x >= body_l and x < body_r:
                                # ombra a terra
                                var sh_a: float = 0.35 - 0.3 * float(y - body_b)
                                col = Color(0.0, 0.0, 0.0, clampf(sh_a, 0.0, 1.0))
                        img.set_pixel(x, y, col)

        # --- runa elementale incisa sul fronte (centro, tra le bande) ---
        var rcx: int = int(cx)
        var rcy: int = 31
        match el:
                C.ElementKind.FIRE:
                        # fiamma stilizzata: triangolo ondulato con cuore
                        for yy in range(-7, 8):
                                var w_fl: float = 4.5 * (1.0 - absf(float(yy)) / 7.5) \
                                                + 1.6 * sin(float(yy) * 1.3)
                                for xx in range(-6, 7):
                                        var d_fl: float = absf(float(xx)) \
                                                        - w_fl * (1.0 - 0.16 * float(yy))
                                        if d_fl <= 0.0 and not (yy > 3 and absf(float(xx)) < 1.0):
                                                _rune_px(img, rcx + xx, rcy + yy, rune)
                C.ElementKind.FROST:
                        # cristallo a 6 braccia con tacche
                        for a in 6:
                                var ang: float = TAU * float(a) / 6.0
                                for r in range(1, 8):
                                        var px: int = rcx + int(round(cos(ang) * float(r) * 1.15))
                                        var py: int = rcy + int(round(sin(ang) * float(r)))
                                        _rune_px(img, px, py, rune)
                                        if r >= 3:
                                                _rune_px(img, px + (1 if a % 2 == 0 else -1),
                                                                py - 1, rune)
                        _rune_px(img, rcx, rcy, rune)
                C.ElementKind.LIGHTNING:
                        # saetta a zigzag
                        var pts := [Vector2i(2, -7), Vector2i(-2, -2), Vector2i(1, -1),
                                        Vector2i(-2, 5), Vector2i(0, 3), Vector2i(3, -3),
                                        Vector2i(1, 7)]
                        # disegno segmento per segmento (spessore 2)
                        for s_idx in range(pts.size() - 1):
                                var p_from: Vector2i = pts[s_idx] + Vector2i(rcx, rcy)
                                var p_to: Vector2i = pts[s_idx + 1] + Vector2i(rcx, rcy)
                                var steps: int = maxi(absi(p_to.x - p_from.x),
                                                absi(p_to.y - p_from.y)) * 2 + 1
                                for st_i in steps:
                                        var f: float = float(st_i) / float(steps - 1)
                                        var lx: int = int(round(lerpf(
                                                        float(p_from.x), float(p_to.x), f)))
                                        var ly: int = int(round(lerpf(
                                                        float(p_from.y), float(p_to.y), f)))
                                        _rune_px(img, lx, ly, rune)
                                        _rune_px(img, lx + 1, ly, rune)
                C.ElementKind.POISON:
                        # goccia con bolle
                        for yy in range(-7, 8):
                                var w_dr: float = 4.8 * sin(PI * clampf(
                                                (float(yy) + 7.0) / 15.0, 0.02, 0.98)) \
                                                * (1.0 if yy < 4 else 0.92)
                                for xx in range(-6, 7):
                                        if absf(float(xx)) <= w_dr:
                                                _rune_px(img, rcx + xx, rcy + yy, rune)
                        # bollicine di fianco
                        _rune_px(img, rcx - 7, rcy - 2, rune)
                        _rune_px(img, rcx - 8, rcy - 2, rune)
                        _rune_px(img, rcx + 7, rcy + 3, rune)
                        _rune_px(img, rcx + 7, rcy + 4, rune)
                        _rune_px(img, rcx + 8, rcy + 3, rune)

        var tex := ImageTexture.create_from_image(img)
        _tex_cache[el] = tex
        return tex


# Pixel di runa: colore elementale con bordo scuro (incisione).
static func _rune_px(img: Image, x: int, y: int, rune: Color) -> void:
        if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
                return
        var cur: Color = img.get_pixel(x, y)
        if cur.a < 0.5:
                return
        # bordo inciso sopra/sotto
        var above: Color = img.get_pixel(x, maxf(0.0, float(y - 1)))
        if above.a > 0.5 and above != rune:
                img.set_pixel(x, maxi(0, y - 1), above.darkened(0.42))
        img.set_pixel(x, y, Color(rune.r, rune.g, rune.b, 1.0))


# Hash deterministico 2D -> [0,1) per la venatura del legno (no RNG a runtime).
static func _hash2(a: int, b: int) -> float:
        var h: int = a * 374761393 + b * 668265263
        h = (h ^ (h >> 13)) * 1274126177
        return float(absi(h % 10000)) / 10000.0

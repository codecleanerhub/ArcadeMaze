## BossArenaPillar.gd — TASK 39 (L'Arena del Boss).
##
## PILASTRO ELEMENTALE: 4 colonne-condotto a tema dell'elemento DEBOLE del
## boss, disposte nell'arena. Meccanica:
##   * il player (proiettili e fendenti reliquia) le frantuma in 3 colpi:
##     a ogni colpo compaiono crepe e schegge mancanti + flash + scintille
##   * i PROIETTILI DEL BOSS vengono BLOCCATI (consumati) e infliggono 1
##     danno al pilastro: la copertura si consuma durante lo scontro
##   * al crollo: scricchiolio, polvere, la colonna si abbatte e spawna 5
##     frammenti (ArenaDebris) lanciati a raggiera che danneggiano il boss
##   * sul fondo resta un cumulo di macerie (feedback permanente)
##
## GRAFICA (curata, zero asset esterni): base a gradini con smusso, fusto
## con scanalature verticali (coste chiare/scura alternate), capitello a
## trapezio + abaco, banda runica centrale che PULSA nel colore dell'elemento,
## crepe procedurali deterministiche per stato di danno, micro-shake al
## colpo, tremolio prima del crollo e polvere al tonfo.
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const DebrisClass = preload("res://scripts/entities/ArenaDebris.gd")

enum PillarState { STANDING, COLLAPSING, RUBBLE }

const SHAKE_MS: float = 140.0
const COLLAPSE_MS: float = 430.0
const PILLAR_W: float = 46.0
const PILLAR_H: float = 112.0

var hp: int = C.BOSS_ARENA_PILLAR_HP
var element: int = C.ElementKind.FIRE
var state: int = PillarState.STANDING
var pillar_index: int = 0

var _t: float = 0.0
var _hit_flash_ms: float = 0.0
var _collapse_ms: float = 0.0
var _seed: float = 0.0
var _pal: Dictionary = {}
var _debris_parent: Node = null
var _fragments_spawned: bool = false
# crepe deterministiche: [progress_along_shaft, side_offset, depth]
var _cracks: Array = []


## `spawn_pos` coordinate MONDO del CENTRO del pilastro.
## `el` elemento (tema) = debolezza del boss. `idx` 0..3 (variazioni forma).
func setup(spawn_pos: Vector2, el: int, idx: int, debris_parent: Node) -> void:
        position = spawn_pos
        element = el
        pillar_index = idx
        _pal = C.get_element_palette(el)
        _debris_parent = debris_parent
        _seed = float(idx) * 17.31 + 3.7
        _generate_cracks()


func _ready() -> void:
        z_index = 14
        process_mode = Node.PROCESS_MODE_PAUSABLE
        add_to_group("arena_pillars")


func _generate_cracks() -> void:
        _cracks.clear()
        # una crepa maggiore per punto danno (deterministica per pilastro)
        for d in C.BOSS_ARENA_PILLAR_HP:
                var prog: float = 0.22 + 0.62 * absf(sin(_seed * 3.1 + float(d) * 2.63))
                _cracks.append({
                        "prog": prog,
                        "side": 1.0 if fmod(_seed + float(d), 2.0) < 1.0 else -1.0,
                        "depth": 4.0 + 5.0 * absf(cos(_seed + float(d) * 1.9)),
                        "wav": 0.5 + absf(sin(_seed * 0.7 + float(d))),
                })


func _process(delta: float) -> void:
        _t += delta
        match state:
                PillarState.STANDING:
                        if _hit_flash_ms > 0.0:
                                _hit_flash_ms -= delta * 1000.0
                PillarState.COLLAPSING:
                        _collapse_ms -= delta * 1000.0
                        if _collapse_ms <= 0.0:
                                state = PillarState.RUBBLE
                        elif not _fragments_spawned and _collapse_ms < COLLAPSE_MS * 0.55:
                                _spawn_fragments()
                PillarState.RUBBLE:
                        pass
        queue_redraw()


## Un colpo (proiettile player, fendente reliquia, proiettile boss).
## Ritorna true se QUESTA chiamata ha abbattuto il pilastro.
func take_hit() -> bool:
        if state != PillarState.STANDING:
                return false
        hp -= 1
        _hit_flash_ms = SHAKE_MS
        if hp <= 0:
                collapse()
                return true
        return false


func collapse() -> void:
        if state != PillarState.STANDING:
                return
        state = PillarState.COLLAPSING
        _collapse_ms = COLLAPSE_MS
        _fragments_spawned = false
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.PILLAR_COLLAPSE)
        if EffectsManager:
                EffectsManager.screen_shake(7.0, 0.35)


func is_standing() -> bool:
        return state == PillarState.STANDING


# Fragmenti lanciati a raggiera (il controller li registra nel gruppo
# arena_debris e li conteggia per il rinnovo dell'arena).
func _spawn_fragments() -> void:
        _fragments_spawned = true
        if _debris_parent == null:
                _debris_parent = get_parent()
        var tint: Color = _pal.get("color", Color.WHITE)
        var n: int = C.BOSS_ARENA_PILLAR_FRAGMENTS
        for i in n:
                var ang: float = TAU * float(i) / float(n) + _seed * 0.37
                var speed: float = 4.2 + 2.6 * absf(sin(_seed + float(i) * 2.1))
                var vel: Vector2 = Vector2(cos(ang), sin(ang) * 0.82) * speed
                var frag: Node2D = DebrisClass.new()
                _debris_parent.add_child(frag)
                if frag.has_method("setup"):
                        frag.setup(position + vel.normalized() * 18.0, vel, tint,
                                        0.85 + 0.45 * absf(cos(_seed + float(i))))
        # polvere del crollo
        if EffectsManager:
                for i in 3:
                        var puff: Node2D = EffectsManager.spawn_explosion(
                                        position + Vector2(randf_range(-14.0, 14.0),
                                                        randf_range(0.0, 20.0)),
                                        Color(0.42, 0.38, 0.34), 10, 0.9)
                        _debris_parent.add_child(puff)


# ============================================================================
# Rendering
# ============================================================================

func _draw() -> void:
        match state:
                PillarState.STANDING:
                        _draw_standing()
                PillarState.COLLAPSING:
                        _draw_collapsing()
                PillarState.RUBBLE:
                        _draw_rubble()


func _draw_standing() -> void:
        var col: Color = _pal.get("color", Color.WHITE)
        var glow: Color = _pal.get("glow", Color.WHITE)
        var wood: Color = _pal.get("wood", Color(0.3, 0.3, 0.3))
        # tonalita' pietra del pilastro derivata dal tema
        var stone: Color = Color(wood.r * 1.9 + 0.16, wood.g * 1.9 + 0.16,
                        wood.b * 1.9 + 0.17)
        var stone_dark: Color = stone.darkened(0.38)
        var stone_light: Color = stone.lightened(0.22)

        # micro-shake mentre lampeggia il colpo subito
        var shake_x: float = 0.0
        if _hit_flash_ms > 0.0:
                shake_x = sin(_t * 90.0) * 2.2 * (_hit_flash_ms / SHAKE_MS)
        var ox: float = shake_x
        var top: float = -PILLAR_H * 0.5
        var bottom: float = PILLAR_H * 0.5
        var hw: float = PILLAR_W * 0.5

        # 0) ombra a terra (ellisse)
        draw_circle(Vector2(0.0, bottom - 4.0), PILLAR_W * 0.62,
                        Color(0.0, 0.0, 0.0, 0.30))

        # 1) base a due gradini con smusso
        _draw_block(Vector2(ox, bottom - 8.0), PILLAR_W * 1.02, 14.0,
                        stone, stone_dark, stone_light)
        _draw_block(Vector2(ox, bottom - 18.0), PILLAR_W * 0.86, 10.0,
                        stone, stone_dark, stone_light)

        # 2) fusto con costature verticali (5 coste)
        var shaft_w: float = PILLAR_W * 0.72
        var shaft_top: float = top + 22.0
        var shaft_bottom: float = bottom - 20.0
        draw_rect(Rect2(ox - shaft_w * 0.5, shaft_top,
                        shaft_w, shaft_bottom - shaft_top), stone, true)
        for i in 5:
                var fx: float = ox - shaft_w * 0.5 + shaft_w * (0.12 + 0.19 * float(i))
                if i % 2 == 0:
                        draw_rect(Rect2(fx, shaft_top, 2.6,
                                        shaft_bottom - shaft_top), stone_dark, true)
                else:
                        draw_rect(Rect2(fx, shaft_top, 2.2,
                                        shaft_bottom - shaft_top), stone_light, true)
        # bordi del fusto (cilindro)
        draw_rect(Rect2(ox - shaft_w * 0.5, shaft_top, 2.4,
                        shaft_bottom - shaft_top), stone_dark, true)
        draw_rect(Rect2(ox + shaft_w * 0.5 - 2.4, shaft_top, 2.4,
                        shaft_bottom - shaft_top), stone_dark, true)

        # 3) banda runica centrale che PULSA (condotto elementale)
        var band_c: float = (shaft_top + shaft_bottom) * 0.5
        var pulse: float = 0.55 + 0.45 * sin(_t * 2.6 + _seed)
        draw_rect(Rect2(ox - shaft_w * 0.5 - 2.0, band_c - 8.0,
                        shaft_w + 4.0, 16.0), stone_dark, true)
        for i in 4:
                var rx: float = ox - shaft_w * 0.5 + 4.0 \
                                + (shaft_w - 8.0) * (float(i) + 0.5) / 4.0
                draw_circle(Vector2(rx, band_c), 2.4,
                                Color(col.r, col.g, col.b, 0.55 + 0.45 * pulse))
        # alone elementale attorno alla banda
        draw_circle(Vector2(ox, band_c), shaft_w * 0.85,
                        Color(glow.r, glow.g, glow.b, 0.10 + 0.07 * pulse))

        # 4) capitello: echino (trapezio) + abaco (lastra)
        var ech_h: float = 10.0
        var ech_top: float = shaft_top - ech_h
        var ech_pts := PackedVector2Array([
                Vector2(ox - shaft_w * 0.5, shaft_top),
                Vector2(ox - shaft_w * 0.5 - 3.0, shaft_top - ech_h * 0.6),
                Vector2(ox + shaft_w * 0.5 + 3.0, shaft_top - ech_h * 0.6),
                Vector2(ox + shaft_w * 0.5, shaft_top),
        ])
        draw_colored_polygon(ech_pts, stone_dark)
        _draw_block(Vector2(ox, ech_top - 2.0), PILLAR_W * 0.94, 9.0,
                        stone, stone_dark, stone_light)

        # 5) crepe per i colpi subiti (hp mancanti = creche visibili)
        var damage: int = C.BOSS_ARENA_PILLAR_HP - hp
        for d in damage:
                if d >= _cracks.size():
                        break
                var cr: Dictionary = _cracks[d]
                _draw_crack(ox, shaft_top, shaft_bottom, shaft_w, cr)

        # 6) flash bianco del colpo
        if _hit_flash_ms > 0.0:
                var fl: float = _hit_flash_ms / SHAKE_MS
                draw_rect(Rect2(ox - hw, top, PILLAR_W, PILLAR_H),
                                Color(1.0, 1.0, 1.0, 0.28 * fl), true)


func _draw_collapsing() -> void:
        var k: float = 1.0 - clampf(_collapse_ms / COLLAPSE_MS, 0.0, 1.0)
        var stone: Color = Color(_pal.get("wood", Color(0.3, 0.3, 0.3)).r * 1.9 + 0.16,
                        _pal.get("wood", Color(0.3, 0.3, 0.3)).g * 1.9 + 0.16,
                        _pal.get("wood", Color(0.3, 0.3, 0.3)).b * 1.9 + 0.17)
        # tremolio crescente + colonna che affonda e si inclina
        var tremble: float = (1.0 - k) * 3.0 * sin(_t * 63.0)
        var sink: float = k * k * PILLAR_H * 0.42
        var tilt: float = k * deg_to_rad(7.0 + 5.0 * sin(_seed))
        draw_set_transform(Vector2(tremble, sink), tilt, Vector2.ONE)
        # fusto semplificato che sprofonda
        var shaft_w: float = PILLAR_W * 0.72
        draw_rect(Rect2(-shaft_w * 0.5, -PILLAR_H * 0.5 + 22.0,
                        shaft_w, PILLAR_H - 42.0), stone, true)
        for i in 5:
                var fx: float = -shaft_w * 0.5 + shaft_w * (0.12 + 0.19 * float(i))
                var flute_col: Color = stone.darkened(0.3) if i % 2 == 0 \
                                else stone.lightened(0.18)
                draw_rect(Rect2(fx, -PILLAR_H * 0.5 + 22.0, 2.4, PILLAR_H - 42.0),
                                flute_col, true)
        # blocchi che schizzano via durante il crollo
        for i in 4:
                var ang: float = PI + TAU * 0.5 * float(i) / 4.0
                var dist: float = k * (30.0 + 22.0 * sin(_seed + float(i) * 1.7))
                draw_rect(Rect2(cos(ang) * dist - 4.0, sin(ang) * dist * 0.4 - 4.0,
                                8.0, 8.0), stone.darkened(0.15), true)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # polvere bassa
        for i in 3:
                var dk: float = clampf(k * 1.4 - float(i) * 0.12, 0.0, 1.0)
                draw_circle(Vector2(-26.0 + float(i) * 26.0, PILLAR_H * 0.5 - 10.0),
                                (12.0 + 26.0 * dk) * (1.0 - 0.3 * float(i)),
                                Color(0.46, 0.42, 0.38, 0.30 * (1.0 - dk * 0.5)))


func _draw_rubble() -> void:
        var stone: Color = Color(_pal.get("wood", Color(0.3, 0.3, 0.3)).r * 1.9 + 0.16,
                        _pal.get("wood", Color(0.3, 0.3, 0.3)).g * 1.9 + 0.16,
                        _pal.get("wood", Color(0.3, 0.3, 0.3)).b * 1.9 + 0.17)
        var col: Color = _pal.get("color", Color.WHITE)
        # ombra del cumulo
        draw_circle(Vector2(0.0, PILLAR_H * 0.5 - 12.0), PILLAR_W * 0.72,
                        Color(0.0, 0.0, 0.0, 0.28))
        # cumulo: 3 blocchi irregolari sovrapposti + sassolini
        var mound := [
                {"p": Vector2(-14.0, 10.0), "s": Vector2(24.0, 13.0)},
                {"p": Vector2(10.0, 8.0), "s": Vector2(22.0, 11.0)},
                {"p": Vector2(-2.0, -4.0), "s": Vector2(26.0, 14.0)},
        ]
        for m in mound:
                draw_rect(Rect2(m.p - m.s * 0.5, m.s), stone.darkened(0.1), true)
                draw_rect(Rect2(m.p - m.s * 0.5, m.s * 0.32), stone.lightened(0.12), true)
        for i in 5:
                var ang: float = _seed + float(i) * 1.9
                var rr: float = 22.0 + 12.0 * absf(sin(_seed * 2.0 + float(i)))
                draw_circle(Vector2(cos(ang) * rr,
                                PILLAR_H * 0.5 - 12.0 + sin(ang) * rr * 0.4),
                                2.6, stone.darkened(0.25))
        # braci elementali morenti nel cumulo
        var ember: float = 0.35 + 0.30 * sin(_t * 2.0 + _seed)
        for i in 3:
                draw_circle(Vector2(-8.0 + float(i) * 8.0, 2.0 + 4.0 * sin(_seed + float(i))),
                                1.8, Color(col.r, col.g, col.b, ember * (0.7 - 0.15 * float(i))))


# Blocco 3D: faccia frontale + bordo superiore illuminato + bordo inferiore
# in ombra + spigoli laterali scuri.
func _draw_block(center: Vector2, w: float, h: float, base: Color,
                dark: Color, light: Color) -> void:
        var r: Rect2 = Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
        draw_rect(r, base, true)
        draw_rect(Rect2(r.position, Vector2(w, 2.6)), light, true)
        draw_rect(Rect2(Vector2(r.position.x, r.end.y - 2.6), Vector2(w, 2.6)), dark, true)
        draw_rect(Rect2(r.position, Vector2(2.2, h)), dark, true)
        draw_rect(Rect2(Vector2(r.end.x - 2.2, r.position.y), Vector2(2.2, h)), dark, true)


# Crepa a zigzag verticale con diramazione, deterministica.
func _draw_crack(ox: float, shaft_top: float, shaft_bottom: float,
                shaft_w: float, cr: Dictionary) -> void:
        var prog: float = cr.get("prog", 0.5)
        var side: float = cr.get("side", 1.0)
        var depth: float = cr.get("depth", 6.0)
        var wav: float = cr.get("wav", 0.7)
        var y0: float = lerpf(shaft_top, shaft_bottom, prog)
        var dark: Color = Color(0.08, 0.07, 0.07, 0.9)
        var pts := PackedVector2Array()
        var n_seg: int = 5
        for i in n_seg + 1:
                var yy: float = y0 + float(i) * 9.0
                var wob: float = side * depth * sin(float(i) * wav * 1.8 + _seed)
                pts.append(Vector2(ox + wob, yy))
        if pts.size() >= 2:
                draw_polyline(pts, dark, 2.2)
                # diramazione a meta'
                var mid_i: int = pts.size() / 2
                var branch: Vector2 = pts[mid_i] + Vector2(side * 7.0, 6.0)
                draw_line(pts[mid_i], branch, dark, 1.6)
        # scheggia mancante sul bordo
        draw_circle(Vector2(ox + side * shaft_w * 0.5, y0), 3.0,
                        Color(0.05, 0.05, 0.06, 0.55))

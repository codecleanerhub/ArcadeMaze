## ArenaDebris.gd — TASK 39 (L'Arena del Boss).
##
## FRAMMENTO DI PILASTRO scagliato dal crollo di BossArenaPillar. Vola con
## velocita' propria + attrito, ruota su se stesso e sfuma; se raggiunge il
## boss (check del controller via gruppo "arena_debris") gli infligge danno
## e viene consumato con un piccolo pop di scintille.
##
## Grafica: poligono irregolare a 5 lati (scheggia di pietra) con faccia
## illuminata e faccia in ombra + scia incandescente elementale (il pilastro
## era un condotto elementale: i frammenti restano "carichi").
extends Node2D

const LIFE_MS: float = 2100.0
const FRICTION: float = 0.972

var velocity: Vector2 = Vector2.ZERO
var spin_deg: float = 0.0
var spin_vel: float = 0.0
var _life_ms: float = LIFE_MS
var _t: float = 0.0
var _size: float = 7.0
var _tint: Color = Color(1.0, 0.62, 0.22)
var _shape: PackedVector2Array = PackedVector2Array()
var _consumed: bool = false


## `from_pos` coordinate MONDO; `vel` px/frame; `tint` colore elementale.
func setup(from_pos: Vector2, vel: Vector2, tint: Color, size_scale: float = 1.0) -> void:
        position = from_pos
        velocity = vel
        _tint = tint
        _size *= size_scale
        # scheggia irregolare deterministica (5 lati)
        _shape = PackedVector2Array()
        for i in 5:
                var ang: float = TAU * float(i) / 5.0 + randf_range(-0.35, 0.35)
                var rr: float = _size * randf_range(0.72, 1.28)
                _shape.append(Vector2(cos(ang), sin(ang)) * rr)
        spin_deg = randf_range(0.0, 360.0)
        spin_vel = randf_range(-9.0, 9.0)


func _ready() -> void:
        z_index = 16
        process_mode = Node.PROCESS_MODE_PAUSABLE
        add_to_group("arena_debris")


func _process(delta: float) -> void:
        if _consumed:
                return
        _t += delta
        _life_ms -= delta * 1000.0
        if _life_ms <= 0.0:
                queue_free()
                return
        var step: float = delta * 60.0
        position += velocity * step
        spin_deg += spin_vel * step
        velocity *= pow(FRICTION, step)
        queue_redraw()


## Chiamato dal controller quando il frammento colpisce il boss: piccolo pop
## di scintille elementali e autodistruzione (una sola botta ciascuno).
func consume_on_boss() -> void:
        if _consumed:
                return
        _consumed = true
        queue_free()


func _draw() -> void:
        if _consumed:
                return
        var k: float = clampf(_life_ms / LIFE_MS, 0.0, 1.0)
        var fade: float = clampf(k * 2.2, 0.0, 1.0)
        # scia incandescente breve
        if velocity.length() > 0.8:
                var dirv: Vector2 = -velocity.normalized()
                draw_circle(dirv * _size * 1.4, _size * 0.42,
                                Color(_tint.r, _tint.g, _tint.b, 0.30 * fade))
                draw_circle(dirv * _size * 2.3, _size * 0.26,
                                Color(_tint.r, _tint.g, _tint.b, 0.16 * fade))
        # corpo: scheggia scura + spigolo illuminato + bordo elementale
        draw_colored_polygon(_shape, Color(0.30, 0.28, 0.27, fade))
        draw_polygon(_shape, PackedColorArray([
                Color(_tint.r, _tint.g, _tint.b, 0.80 * fade),
                Color(_tint.r, _tint.g, _tint.b, 0.80 * fade),
                Color(0.60, 0.58, 0.55, fade),
                Color(0.42, 0.40, 0.38, fade),
                Color(0.42, 0.40, 0.38, fade),
        ]))
        # rimasuglio di carica elementale (brillio al centro)
        draw_circle(Vector2.ZERO, _size * 0.3,
                        Color(_tint.r, _tint.g, _tint.b,
                                        (0.35 + 0.3 * sin(_t * 15.0)) * fade))

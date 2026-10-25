## ArenaDebris.gd — TASK 39 (L'Arena del Boss) / TASK 50 rielaborato.
##
## FRAMMENTO DI PIETRA scagliato dal crollo di un'architettura dell'arena
## (pilastri e, dal TASK 50, i MURO-Rovina del labirinto spezzato). Vola con
## velocita' propria + attrito, ruota su se stesso e sfuma; se raggiunge il
## boss (check del controller via gruppo "arena_debris") gli infligge danno
## e viene consumato.
##
## Grafica TASK 50 (richiesta utente: "si vedono ancora i pallini arancioni
## quando si rompe un elemento"): via OGNI tinta elementale, scia
## incandescente e brillio luminoso — ora e' una SCHIGGIA DI CALCARE grigia
## con faccia illuminata, faccia in ombra e punteggiatura minerale, come le
## macerie delle mura della cripta. Il parametro `tint` resta nell'API per
## compatibilita' ma viene IGNORATO.
extends Node2D

const LIFE_MS: float = 2100.0
const FRICTION: float = 0.972

var velocity: Vector2 = Vector2.ZERO
var spin_deg: float = 0.0
var spin_vel: float = 0.0
var _life_ms: float = LIFE_MS
var _t: float = 0.0
var _size: float = 7.0
var _shape: PackedVector2Array = PackedVector2Array()
var _consumed: bool = false
var _speckles: Array = []


## `from_pos` coordinate MONDO; `vel` px/frame; `tint` IGNORATO (TASK 50:
## sempre pietra grigia, niente caricature arancioni).
func setup(from_pos: Vector2, vel: Vector2, _tint: Color, size_scale: float = 1.0) -> void:
        position = from_pos
        velocity = vel
        _size *= size_scale
        # scheggia irregolare deterministica (5-6 lati)
        var sides: int = 5 + (randi() % 2)
        _shape = PackedVector2Array()
        for i in sides:
                var ang: float = TAU * float(i) / float(sides) + randf_range(-0.35, 0.35)
                var rr: float = _size * randf_range(0.72, 1.28)
                _shape.append(Vector2(cos(ang), sin(ang)) * rr)
        # punteggiatura minerale (2-3 granuli scuri fissi per scheggia)
        for i in (2 + randi() % 2):
                _speckles.append(Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * _size)
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
        # --- TASK 50: SCHIGGIA DI PIETRA pura ---
        # corpo: calcare grigio con faccia illuminata in alto e ombra in basso
        draw_colored_polygon(_shape, Color(0.33, 0.34, 0.39, fade))
        draw_polygon(_shape, PackedColorArray([
                Color(0.74, 0.73, 0.70, fade),   # luce fredda dall'alto
                Color(0.60, 0.59, 0.56, fade),
                Color(0.47, 0.47, 0.50, fade),
                Color(0.36, 0.36, 0.40, fade),
                Color(0.29, 0.29, 0.33, fade),   # fondo in ombra
        ]))
        # punteggiatura minerale (granuli scuri)
        for sp in _speckles:
                draw_circle(sp, _size * 0.10, Color(0.22, 0.22, 0.24, 0.75 * fade))
        # spigolo illuminato: sottile linea di luce sul bordo superiore
        if _shape.size() >= 2:
                var a0: Vector2 = _shape[0].normalized() * _size
                var a1: Vector2 = _shape[1].normalized() * _size
                draw_line(a0, a1, Color(0.88, 0.87, 0.82, 0.55 * fade), 1.0)

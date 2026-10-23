## IceBeamEffect.gd — TASK 50 (pergamena del GHIACCIO).
##
## RAGGIO CONGELANTE sparato dal player che ha equipaggiato la pergamena
## del ghiaccio: beam dal muzzle del player fino al primo muro (o alla
## gittata massima). Triplo tratto (alone celeste-ghiaccio largo, tratto
## pallido, core bianco-freddo) con leggero wobble perpendicolare,
## scintille di brina che viaggiano lungo il raggio, bagliore al muzzle
## e all'impatto, anello di brina che si espande all'estremita'.
##
## Pattern LightningStrikeEffect: PROCESS_MODE_PAUSABLE, z_index 46
## (sopra le entita', sotto HUD), autodistruzione a fine durata (~420ms).
extends Node2D

const DURATION_MS: float = 420.0

var _to_local: Vector2 = Vector2(200.0, 0.0)
var _life_ms: float = DURATION_MS
var _t: float = 0.0
var _seed: float = 0.0


## `from_pos`: coordinate MONDO del muzzle del player (position del nodo).
## `to_pos`: coordinate MONDO della fine del raggio (muro o gittata max).
func setup(from_pos: Vector2, to_pos: Vector2) -> void:
        position = from_pos
        _to_local = to_pos - from_pos


func _ready() -> void:
        z_index = 46
        process_mode = Node.PROCESS_MODE_PAUSABLE
        _seed = randf() * 100.0


func _process(delta: float) -> void:
        _t += delta
        _life_ms -= delta * 1000.0
        if _life_ms <= 0.0:
                queue_free()
                return
        queue_redraw()


func _draw() -> void:
        var alpha: float = clampf(_life_ms / DURATION_MS, 0.0, 1.0)
        # il colpo pieno dura i primi 2/3 della durata, poi sfuma
        var strike: float = clampf(_life_ms / (DURATION_MS * 0.66), 0.0, 1.0)
        # pulsazione nervosa del raggio (il beam "vive")
        var flick: float = 0.72 + 0.28 * sin(_t * 39.0 + _seed)
        var a: float = strike * flick

        var length: float = _to_local.length()
        if length < 1.0:
                return
        var dir: Vector2 = _to_local / length
        var normal: Vector2 = Vector2(-dir.y, dir.x)

        # --- 1) beam: zigzag morbido rigenerato a ogni draw ---------------
        var pts := PackedVector2Array()
        var segments: int = maxi(4, int(length / 40.0))
        for s in range(segments + 1):
                var t0: float = float(s) / float(segments)
                # wobble perpendicolare delicato (onde di freddo)
                var wob: float = sin(t0 * 9.0 + _t * 15.0 + _seed) \
                                * (3.5 * t0 * (1.0 - t0) * 4.0)
                pts.append(dir * (length * t0) + normal * wob)
        # alone esterno largo CELESTE GHIACCIO
        draw_polyline(pts, Color(0.35, 0.80, 1.0, 0.30 * a), 13.0)
        # tratto intermedio pallido-azzurro
        draw_polyline(pts, Color(0.72, 0.90, 1.0, 0.65 * a), 5.0)
        # core bianco-freddo
        draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.97 * a), 2.0)

        # --- 2) scintille di brina che viaggiano lungo il raggio ----------
        for k in 6:
                var sp_t: float = fmod(_t * 1.6 + float(k) * 0.17, 1.0)
                var sp_pos: Vector2 = dir * (length * sp_t) \
                                + normal * sin(_t * 11.0 + float(k) * 2.3) * 6.0
                draw_circle(sp_pos, 1.8 * (1.0 - sp_t) + 0.6,
                                Color(0.88, 0.97, 1.0, 0.75 * a * (1.0 - sp_t)))

        # --- 3) bagliore al muzzle e all'impatto ---------------------------
        for i in 3:
                var rr: float = (16.0 - 4.0 * float(i)) * flick
                draw_circle(Vector2.ZERO, rr, Color(0.35, 0.80, 1.0, 0.20 * a))
        draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 1.0, 0.90 * strike))
        var glow_r: float = (26.0 + 8.0 * sin(_t * 25.0)) * flick
        for i in 3:
                draw_circle(_to_local, glow_r * (1.0 - 0.25 * float(i)),
                                Color(0.35, 0.80, 1.0, 0.18 * a))
        draw_circle(_to_local, 6.0, Color(1.0, 1.0, 1.0, 0.90 * strike))

        # --- 4) anello di brina che si espande all'estremita' --------------
        var ring_k: float = 1.0 - _life_ms / DURATION_MS   # 0 -> 1
        var ring_r: float = 10.0 + 52.0 * ring_k
        draw_arc(_to_local, ring_r, 0.0, TAU, 32,
                        Color(0.55, 0.88, 1.0, 0.55 * (1.0 - ring_k)), 3.0)

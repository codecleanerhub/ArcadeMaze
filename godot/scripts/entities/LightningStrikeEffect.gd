## LightningStrikeEffect.gd — TASK 36 (pergamene piu' evidenti).
##
## FULMINE CHE SI ABBATE AL SUOLO sulla cella della pergamena al momento
## dell'apparizione: saetta verticale dall'alto dello schermo (oltre il
## bordo superiore) fino al punto d'impatto, rigenerata a OGNI frame
## (flicker elettrico realistico come LightningArcEffect), triplo tratto
## alone-tinto + tratto pallido + core bianco-caldo, ramificazioni
## secondarie, bagliore d'impatto pulsante, onda d'urto ad anello che si
## espande sul terreno e braci che risalgono lungo la saetta.
##
## L'alone esterno e' TINTO con il colore della pergamena (arancio fuoco
## per il terremoto, viola psichico per le voragini): il fulmine resta
## bianco-caldo ma lascia un'impronta cromatica riconoscibile.
##
## Pattern LightningArcEffect: PROCESS_MODE_PAUSABLE, z_index 46 (sopra
## l'arco della Verga, sotto HUD), autodistruzione a fine durata (~750ms).
extends Node2D

const DURATION_MS: float = 750.0

## Impatto a terra (position del nodo). La saetta parte da qui e sale.
var _tint: Color = Color(1.0, 0.62, 0.22)
var _bolt_height: float = 760.0
var _life_ms: float = DURATION_MS
var _t: float = 0.0
var _seed: float = 0.0


## `impact_pos`: coordinate MONDO del punto d'impatto (la pergamena).
## `tint`: colore della pergamena (alone + onda d'urto + braci).
func setup(impact_pos: Vector2, tint: Color) -> void:
        position = impact_pos
        _tint = tint
        # la saetta parte sempre da SOPRA il bordo superiore dello schermo
        _bolt_height = maxf(360.0, impact_pos.y + 60.0)


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
        # il colpo pieno dura la prima meta' della durata, poi sfuma
        var strike: float = clampf(_life_ms / (DURATION_MS * 0.55), 0.0, 1.0)
        # Flicker: intensita' nervosa (il fulmine "vive")
        var flick: float = 0.70 + 0.30 * sin(_t * 43.0 + _seed)
        var a: float = strike * flick

        # --- 1) saetta verticale: zigzag rigenerato a ogni draw ---------
        var pts := PackedVector2Array()
        var top: Vector2 = Vector2(0.0, -_bolt_height)
        var elbows: int = maxi(3, int(_bolt_height / 34.0))
        for e in range(elbows):
                var t0: float = float(e) / float(elbows)
                # offset orizzontale pseudo-casuale: alternato + jitter
                # (rigenerato ogni draw -> flicker naturale del fulmine)
                var amp: float = (16.0 if e % 2 == 0 else -16.0) \
                                + randf_range(-9.0, 9.0)
                pts.append(top + Vector2(amp, _bolt_height * t0))
        pts.append(Vector2.ZERO)
        if pts.size() >= 2:
                # alone esterno largo TINTO (colore pergamena)
                draw_polyline(pts,
                        Color(_tint.r, _tint.g, _tint.b, 0.30 * a), 13.0)
                # tratto intermedio pallido
                draw_polyline(pts, Color(0.85, 0.90, 1.0, 0.65 * a), 5.0)
                # core bianco-caldo
                draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.97 * a), 2.0)
                # ramificazioni secondarie (micro-raggi)
                for k in 3:
                        var idx: int = (k + 1) * (pts.size() / 4)
                        if idx >= pts.size():
                                idx = pts.size() - 1
                        var from: Vector2 = pts[idx]
                        var ang: float = _t * 7.0 + _seed + float(k) * 2.1
                        var to: Vector2 = from + Vector2(cos(ang),
                                        sin(ang) * 0.4) \
                                        * (26.0 + 10.0 * sin(_t * 19.0))
                        draw_line(from, to,
                                Color(0.90, 0.93, 1.0, 0.50 * a), 1.4)

        # --- 2) impatto a terra: bagliore radiale pulsante tinto ---------
        var glow_r: float = 34.0 + 10.0 * sin(_t * 29.0)
        for i in 4:
                var rr: float = glow_r * (1.0 - 0.22 * float(i))
                draw_circle(Vector2.ZERO, rr,
                        Color(_tint.r, _tint.g, _tint.b, 0.16 * a))
        # nucleo bianco dell'impatto
        draw_circle(Vector2.ZERO, 12.0, Color(1.0, 1.0, 1.0, 0.90 * strike))
        draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 1.0, 0.95 * strike))

        # --- 3) onda d'urto ad anello che si espande sul suolo ----------
        var ring_k: float = 1.0 - _life_ms / DURATION_MS   # 0 -> 1
        var ring_r: float = 18.0 + 96.0 * ring_k
        draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 40,
                Color(_tint.r, _tint.g, _tint.b, 0.55 * (1.0 - ring_k)), 3.5)

        # --- 4) braci che risalgono lungo la saetta ----------------------
        for k in 5:
                var emb_t: float = fmod(_t * 0.7 + float(k) * 0.23, 1.0)
                var emb_y: float = -emb_t * 120.0
                var emb_x: float = sin(_t * 9.0 + float(k) * 2.7) * 14.0 * emb_t
                draw_circle(Vector2(emb_x, emb_y),
                        2.2 * (1.0 - emb_t) + 0.8,
                        Color(1.0, 0.95, 0.80, 0.70 * alpha * (1.0 - emb_t)))

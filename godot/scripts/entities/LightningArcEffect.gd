## LightningArcEffect.gd — TASK 23 (fix utente: "il fulmine a catena non
## mostra il fulmine, si dovrebbe vedere la traiettoria del fulmine che
## attraversa i nemici").
##
## Effetto Node2D che disegna UN ARCO DI FULMINE attraverso la sequenza di
## punti fornita (es. player → nemico1 → nemico2 → nemico3): spezzata
## zigzag rigenerata a ogni frame (flicker elettrico realistico), doppio
## tratto alone/core bianco, impatti luminosi sui nodi e micro-raggi secondari.
##
## Pattern SoulTransferEffect: PROCESS_MODE_PAUSABLE, z_index 45,
## autodistruzione a fine durata (~340 ms). Spawnato dai controller
## (MainGameController/BossRoomController) al proc della Verga della Tempesta.
extends Node2D

const DURATION_MS: float = 340.0

## Percorso dell'arco (coordinate MONDO). Punti consecutivi = segmenti.
var _points: Array = []
var _life_ms: float = DURATION_MS
var _t: float = 0.0
## Seed per lo zigzag (varia per effetto, rigenerato ogni draw via randf).
var _seed: float = 0.0


## `path`: Array[Vector2] — il percorso in coordinate mondo
## (player → nemici colpiti in catena).
func setup(path: Array) -> void:
        _points = path.duplicate()
        _seed = randf() * 100.0


func _ready() -> void:
        z_index = 45
        process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
        _t += delta
        _life_ms -= delta * 1000.0
        if _life_ms <= 0.0:
                queue_free()
                return
        queue_redraw()


func _draw() -> void:
        if _points.size() < 2:
                return
        var alpha: float = clampf(_life_ms / DURATION_MS, 0.0, 1.0)
        # Flicker: intensità nervosa (il fulmine "vive").
        var flick: float = 0.75 + 0.25 * sin(_t * 47.0 + _seed)
        alpha *= flick
        # Costruisci la spezzata zigzag completa (punti locali).
        var pts: PackedVector2Array = PackedVector2Array()
        for i in range(_points.size() - 1):
                var a: Vector2 = _points[i]
                var b: Vector2 = _points[i + 1]
                var seg: Vector2 = b - a
                var seg_len: float = seg.length()
                if seg_len < 1.0:
                        continue
                var n: Vector2 = seg.normalized()
                var perp: Vector2 = Vector2(-n.y, n.x)
                # Numero di gomiti in base alla lunghezza (ogni ~26px un gomito).
                var elbows: int = maxi(2, int(seg_len / 26.0))
                for e in range(elbows):
                        var t0: float = float(e) / float(elbows)
                        # offset perpendicolare pseudo-casuale (rigenerato ogni
                        # draw -> flicker naturale del fulmine).
                        var amp: float = (3.5 if e % 2 == 0 else -3.5) \
                                        + randf_range(-2.5, 2.5)
                        pts.append(a + n * seg_len * t0 + perp * amp)
                pts.append(b)
        if pts.size() < 2:
                return
        # 1) alone esterno ciano largo
        draw_polyline(pts, Color(0.45, 0.70, 1.0, 0.35 * alpha), 7.0)
        # 2) tratto intermedio azzurro
        draw_polyline(pts, Color(0.62, 0.84, 1.0, 0.75 * alpha), 3.2)
        # 3) core bianco vivo
        draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.95 * alpha), 1.3)
        # 4) impatti luminosi sui nodi del percorso (i nemici attraversati).
        for pt in _points:
                var lp: Vector2 = pt
                draw_circle(lp, 5.5 + 1.5 * sin(_t * 31.0),
                        Color(0.70, 0.88, 1.0, 0.55 * alpha))
                draw_circle(lp, 2.6, Color(1.0, 1.0, 1.0, 0.9 * alpha))
        # 5) micro-raggi secondari (ramificazioni) da un paio di nodi.
        for k in mini(2, _points.size()):
                var node_p: Vector2 = _points[k]
                var branch_a: float = _t * 9.0 + _seed + float(k) * 2.4
                var bdir: Vector2 = Vector2(cos(branch_a), sin(branch_a))
                var bend: Vector2 = node_p + bdir * (9.0 + 5.0 * sin(_t * 21.0))
                draw_line(node_p, bend,
                        Color(0.75, 0.90, 1.0, 0.5 * alpha), 1.0)

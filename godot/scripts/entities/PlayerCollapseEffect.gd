## PlayerCollapseEffect.gd — TASK 87: animazione di morte del player
## (richiesta utente: "il player quando finisce l'energia muore accasciandosi
## al pavimento ed emette un suono di sofferenza").
##
## Sequenza (~1.2s, self-driving come SoulTransferEffect — il gioco NON si
## congela, solo la vittima è inerte):
##   1. FALL   (~480ms) — il corpo si accascia: le ginocchia cedono (piccolo
##      sinking), la texture ruota attorno ai piedi (caduta accelerata
##      "in avanti" nella direzione in cui guardava), polvere all'impatto.
##   2. TWITCH (~420ms) — disteso a terra: tremito decrescente (wobble della
##      rotazione) + spirali di polvere/dolore che salgono debolmente.
##   3. FADE   (~260ms) — il corpo sfuma (respawn) o resta fino al cambio
##      scena (morte definitiva).
## Al termine emette `finished`: il controller chiamante decide se
## respawnare (vite residue, pattern respawn_after_soul) o sbloccare il
## player per il flusso continue/game-over (morte definitiva).
##
## Il suono PLAYER_SUFFER lo spawna il controller all'avvio dell'effetto
## (insieme ai SFX di colpo dei chiamanti: layering voluto).
extends Node2D
class_name PlayerCollapseEffect

signal finished

enum Phase { FALL, TWITCH, FADE, DONE }

const FALL_MS: float = 480.0
const TWITCH_MS: float = 420.0
const FADE_MS: float = 260.0
const TOTAL_MS: float = FALL_MS + TWITCH_MS + FADE_MS

# --- Setup (chiamato dal controller PRIMA dell'add_child) --------------------
var victim: CharacterBody2D = null   # player morente (texture/tint corpo)
var death_pos: Vector2 = Vector2.ZERO
var body_tex: Texture2D = null       # frame dello sprite del personaggio
var body_flip_h: bool = false
var body_tint: Color = Color.WHITE

# --- Stato runtime ------------------------------------------------------------
var phase: int = Phase.FALL
var t: float = 0.0
var _impact_done: bool = false
var _dust: Array = []   # {pos, vel, size, life, max}
var _rng := RandomNumberGenerator.new()


# setup(): raccoglie tutto ciò che serve dalla vittima PRIMA che questa
# venga congelata/nascosta (texture del frame corrente, flip, tint), come
# SoulTransferEffect.setup (pattern Task 18).
func setup(p_victim: CharacterBody2D) -> void:
        victim = p_victim
        death_pos = p_victim.get_pixel_pos()
        if p_victim.get("sprite") != null and p_victim.sprite != null \
                        and p_victim.sprite.texture != null:
                body_tex = p_victim.sprite.texture
                body_flip_h = p_victim.sprite.flip_h
        body_tint = p_victim.tint


func _ready() -> void:
        _rng.seed = hash(to_string()) % 2147483647
        process_mode = Node.PROCESS_MODE_PAUSABLE
        z_index = 50
        queue_redraw()


func _process(delta: float) -> void:
        t += delta * 1000.0
        # Impatto: polvere a metà caduta (ginocchia a terra).
        if phase == Phase.FALL and not _impact_done and t > FALL_MS * 0.55:
                _impact_done = true
                _spawn_impact_dust()
        match phase:
                Phase.FALL:
                        if t >= FALL_MS:
                                phase = Phase.TWITCH
                                t = 0.0
                Phase.TWITCH:
                        if t >= TWITCH_MS:
                                phase = Phase.FADE
                                t = 0.0
                Phase.FADE:
                        if t >= FADE_MS:
                                phase = Phase.DONE
                                finished.emit()
                                queue_free()
                                return
        _update_dust(delta)
        queue_redraw()


# ============================================================================
# Rendering (procedurale, coordinate nello spazio dei player — pattern
# SoulTransferEffect._draw_body con pivot ai piedi)
# ============================================================================
func _draw() -> void:
        var alpha: float = 1.0
        var fp: float = 1.0        # progresso caduta (0 in piedi, 1 disteso)
        var wobble: float = 0.0    # tremito da disteso
        match phase:
                Phase.FALL:
                        fp = clampf(t / FALL_MS, 0.0, 1.0)
                Phase.TWITCH:
                        # tremito decrescente: il corpo "respira" un'ultima
                        # volta disteso a terra
                        var k: float = clampf(t / TWITCH_MS, 0.0, 1.0)
                        wobble = sin(t * 0.045) * 0.055 * (1.0 - k)
                Phase.FADE:
                        alpha = clampf(1.0 - t / FADE_MS, 0.0, 1.0)
                _:
                        return
        _draw_dust()
        _draw_body(fp, wobble, alpha)


# --- Corpo: texture della vittima che ruota attorno ai piedi ------------------
# fp = progresso caduta; wobble = tremito; alpha = dissolvenza finale.
func _draw_body(fp: float, wobble: float, alpha: float) -> void:
        var pivot: Vector2 = death_pos + Vector2(0.0, 30.0)  # piedi
        # Le ginocchia cedono: il busto scende un poco PRIMA di ruotare.
        var sink: float = 8.0 * clampf(fp * 2.0, 0.0, 1.0)
        # Rotazione accelerata (gravità): da 0 a ~83°, nella direzione in cui
        # guardava la vittima (cade "in avanti"), + eventuale tremito.
        var fall_sign: float = -1.0 if body_flip_h else 1.0
        var rot: float = fall_sign * (1.45 * fp * fp + wobble)
        var mod_color := Color(body_tint.r, body_tint.g, body_tint.b, alpha)
        # Scurisci leggermente mentre svanisce (spento).
        if alpha < 1.0:
                mod_color = mod_color.darkened((1.0 - alpha) * 0.35)
        if body_tex != null:
                draw_set_transform(pivot + Vector2(0.0, sink), rot,
                                Vector2(-1.0 if body_flip_h else 1.0, 1.0))
                draw_texture_rect(body_tex, Rect2(-32.0, -62.0, 64.0, 64.0),
                                false, mod_color)
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        else:
                # Fallback (texture non disponibile): sagoma che si distende.
                draw_set_transform(pivot + Vector2(0.0, sink), rot, Vector2.ONE)
                draw_colored_polygon(PackedVector2Array([
                                Vector2(-30.0, -58.0), Vector2(30.0, -58.0),
                                Vector2(30.0, -2.0), Vector2(-30.0, -2.0),
                ]), Color(0.22, 0.20, 0.26, alpha * 0.9))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # Ombra a terra sotto il corpo che si accascia (il player nascosto non
        # la disegna più — continuità visiva).
        var shadow_rx: float = 14.0 + 20.0 * fp
        _ellipse_local(pivot, shadow_rx, shadow_rx * 0.38,
                        Color(0.05, 0.05, 0.06, 0.35 * alpha))


# --- Polvere: burst all'impatto + spirali deboli mentre è disteso -------------
func _spawn_impact_dust() -> void:
        var pivot: Vector2 = death_pos + Vector2(0.0, 28.0)
        for i in 8:
                var ang: float = PI + float(i) / 8.0 * PI
                var side: float = -1.0 if body_flip_h else 1.0
                var dir: Vector2 = Vector2(cos(ang) * side, -absf(sin(ang)) * 0.4)
                _dust.append({
                        "pos": pivot + Vector2(rng_side() * 10.0, 0.0),
                        "vel": dir * _rng.randf_range(35.0, 85.0),
                        "size": _rng.randf_range(2.5, 5.0),
                        "col": Color(0.55, 0.50, 0.45, 0.55),
                        "life": _rng.randf_range(420.0, 700.0),
                        "max": 700.0,
                })
        # Un paio di sbuffi anche dal lato opposto (rimbalzio della polvere)
        for i in 2:
                _dust.append({
                        "pos": pivot + Vector2(rng_side() * 22.0, -2.0),
                        "vel": Vector2(rng_side() * _rng.randf_range(10.0, 30.0),
                                        -_rng.randf_range(15.0, 35.0)),
                        "size": _rng.randf_range(4.0, 7.0),
                        "col": Color(0.60, 0.56, 0.50, 0.35),
                        "life": 500.0,
                        "max": 500.0,
                })


func _update_dust(delta: float) -> void:
        var doomed: Array = []
        for i in _dust.size():
                var d: Dictionary = _dust[i]
                d["life"] = float(d["life"]) - delta * 1000.0
                if float(d["life"]) <= 0.0:
                        doomed.append(i)
                        continue
                d["pos"] = (d["pos"] as Vector2) + (d["vel"] as Vector2) * delta
                # la polvere si ferma e si dissolve
                d["vel"] = (d["vel"] as Vector2) * maxf(0.0, 1.0 - 2.2 * delta)
                d["size"] = float(d["size"]) + 6.0 * delta
        for i in range(doomed.size() - 1, -1, -1):
                _dust.remove_at(doomed[i])
        # Spirali deboli mentre è disteso (TWITCH)
        if phase == Phase.TWITCH and _rng.randf() < 0.06:
                _dust.append({
                        "pos": death_pos + Vector2(_rng.randf_range(-26.0, 26.0), -4.0),
                        "vel": Vector2(_rng.randf_range(-6.0, 6.0),
                                        -_rng.randf_range(18.0, 34.0)),
                        "size": _rng.randf_range(2.0, 3.5),
                        "col": Color(0.62, 0.58, 0.52, 0.28),
                        "life": 620.0,
                        "max": 620.0,
                })


func _draw_dust() -> void:
        for d in _dust:
                var f: float = clampf(float(d["life"]) / float(d["max"]), 0.0, 1.0)
                var c: Color = d["col"]
                draw_circle(d["pos"], float(d["size"]),
                                Color(c.r, c.g, c.b, c.a * f))


func rng_side() -> float:
        return _rng.randf_range(-1.0, 1.0)


func _ellipse_local(c: Vector2, rx: float, ry: float, col: Color) -> void:
        if rx <= 0.5 or ry <= 0.5:
                return
        var pts: PackedVector2Array = PackedVector2Array()
        for i in 20:
                var a: float = float(i) / 20.0 * TAU
                pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
        draw_colored_polygon(pts, col)

## SoulTransferEffect.gd — Effetto "trasferimento anima" del FUOCO AMICO
## (Task 18, richiesta utente):
##   1. Il corpo del player ucciso dal compagno si ACCASCA al pavimento
##      (la texture del personaggio ruota attorno ai piedi, con polvere
##      all'impatto) e svanisce pian piano mentre l'anima vola.
##   2. La sua ANIMA (spiritello luminoso con scia eterea e codina
##      ondulata) si solleva dal corpo e VOLA VELOCE verso il player
##      vincitore, inseguendone la posizione live (homing): se il vincitore
##      si muove, l'anima lo insegue.
##   3. All'arrivo: burst di assorbimento con anello di ricarica attorno al
##      vincitore + scintille radiali. Il segnale soul_delivered dice al
##      controller di ricaricare COMPLETAMENTE l'energia del vincitore e di
##      far respawnare la vittima.
##
## Durata tipica: ~0.3s caduta + ~0.25s sollevamento + volo (~0.3-0.7s) +
## ~0.3s burst = 1.2-1.5s totali. Viene aggiunto come figlio del root del
## controller (MainGame/BossRoom): disegnato sopra player e nemici; usa il
## tempo reale di _process (come gli altri effetti Godot-native) e si mette
## in pausa con l'albero di gioco (PROCESS_MODE_PAUSABLE).
extends Node2D

signal soul_delivered  # emesso una sola volta quando l'anima arriva
signal finished        # emesso alla fine del burst, prima del queue_free

# --- Fasi della sequenza -----------------------------------------------------
enum Phase { FALL, RISE, FLY, ABSORB, DONE }

const FALL_MS: float = 320.0        # corpo che si accascia
const RISE_MS: float = 240.0        # anima che si solleva dal corpo
const ABSORB_MS: float = 300.0      # burst di assorbimento sul vincitore
const FLY_SPEED_START: float = 420.0  # px/s iniziali del volo (già veloce)
const FLY_SPEED_MAX: float = 780.0    # px/s a fine accelerazione
const FLY_ACCEL: float = 900.0        # px/s^2 di accelerazione del volo
const ARRIVE_DIST: float = 22.0       # distanza di assorbimento (px)
const TRAIL_MAX: int = 10             # lunghezza della scia eterea

# --- Setup (chiamato dal controller PRIMA dell'add_child) --------------------
var victim: CharacterBody2D = null     # player ucciso (per texture/tint corpo)
var receiver: Node2D = null            # bersaglio dell'anima: player vincitore
                                       # del fuoco amico OPPURE nemico bersaglio
                                       # della bambola voodoo (Task 108: entrambi
                                       # espongono get_pixel_pos per l'homing)
var death_pos: Vector2 = Vector2.ZERO
var body_tex: Texture2D = null         # frame dello sprite della vittima
var body_flip_h: bool = false
var body_tint: Color = Color.WHITE
var soul_color: Color = Color(0.80, 0.95, 1.0, 1.0)

# --- Stato runtime ------------------------------------------------------------
var phase: int = Phase.FALL
var t: float = 0.0
var soul_pos: Vector2 = Vector2.ZERO
var fly_speed: float = FLY_SPEED_START
var last_receiver_pos: Vector2 = Vector2.ZERO
var delivered: bool = false
var _trail: Array[Vector2] = []
var _fly_t: float = 0.0
var _rng := RandomNumberGenerator.new()


# setup(): raccoglie tutto ciò che serve dalla vittima PRIMA che questa
# venga congelata/nascosta (texture del frame corrente, orientamento, tint).
# TASK 108: `p_receiver` e' Node2D (player vincitore del fuoco amico OPPURE
# nemico bersaglio della bambola voodoo: del receiver serve solo la
# posizione viva per l'homing).
func setup(p_victim: CharacterBody2D, p_receiver: Node2D) -> void:
        victim = p_victim
        receiver = p_receiver
        death_pos = p_victim.get_pixel_pos()
        last_receiver_pos = death_pos
        if p_receiver != null and is_instance_valid(p_receiver):
                last_receiver_pos = p_receiver.get_pixel_pos()
        # Texture del corpo: frame corrente dello sprite del personaggio.
        if p_victim.get("sprite") != null and p_victim.sprite != null \
                        and p_victim.sprite.texture != null:
                body_tex = p_victim.sprite.texture
                body_flip_h = p_victim.sprite.flip_h
        body_tint = p_victim.tint
        # L'anima conserva una sfumatura del colore del player morto
        # (P2 blu → anima lievemente azzurra, P1 → bianco-ciano).
        soul_color = Color(
                clampf(0.78 + body_tint.r * 0.20, 0.0, 1.0),
                clampf(0.92 + body_tint.g * 0.08, 0.0, 1.0),
                1.0, 1.0)


## TASK 108 (VOODOO): setup "senza corpo" per il volo di RITORNO dell'anima
## quando il corpo posseduto muore: l'anima vola da `from_pos` a `to_pos`
## fisse (niente homing, niente corpo accasciato da disegnare — il corpo
## del nemico esplode a parte nel controller).
func setup_dummy(from_pos: Vector2, to_pos: Vector2) -> void:
        victim = null
        receiver = null
        death_pos = from_pos
        last_receiver_pos = to_pos
        body_tex = null
        body_flip_h = false
        body_tint = Color.WHITE
        soul_color = Color(0.80, 0.95, 1.0, 1.0)


func _ready() -> void:
        _rng.seed = hash(to_string()) % 2147483647
        # In pausa l'effetto si ferma insieme al gioco (il parent controller
        # è PROCESS_MODE_ALWAYS per gestire il tasto P: senza PAUSABLE qui,
        # l'anima continuerebbe a volare durante la pausa).
        process_mode = Node.PROCESS_MODE_PAUSABLE
        z_index = 50
        soul_pos = death_pos + Vector2(0.0, -10.0)


func _process(delta: float) -> void:
        t += delta * 1000.0
        match phase:
                Phase.FALL:
                        if t >= FALL_MS:
                                phase = Phase.RISE
                                t = 0.0
                                soul_pos = death_pos + Vector2(0.0, -10.0)
                                _trail.clear()
                Phase.RISE:
                        # L'anima sale dal petto del corpo accasciato.
                        var rp: float = clampf(t / RISE_MS, 0.0, 1.0)
                        var eased: float = 1.0 - pow(1.0 - rp, 2.0)
                        soul_pos = death_pos + Vector2(0.0, -10.0 - 42.0 * eased)
                        _push_trail()
                        if t >= RISE_MS:
                                phase = Phase.FLY
                                t = 0.0
                                _fly_t = 0.0
                                fly_speed = FLY_SPEED_START
                Phase.FLY:
                        _fly_t += delta
                        # Homing sulla posizione LIVE del bersaglio (player
                        # vincitore o nemico posseduto: Task 108).
                        if receiver != null and is_instance_valid(receiver) \
                                        and receiver.has_method("get_pixel_pos"):
                                last_receiver_pos = receiver.get_pixel_pos()
                        var to_target: Vector2 = last_receiver_pos - soul_pos
                        var dist: float = to_target.length()
                        fly_speed = minf(FLY_SPEED_MAX, fly_speed + FLY_ACCEL * delta)
                        if dist > 0.001:
                                var step: float = minf(fly_speed * delta, dist)
                                soul_pos += to_target / dist * step
                        _push_trail()
                        if dist <= ARRIVE_DIST or _fly_t > 2.5:
                                _deliver()
                Phase.ABSORB:
                        if t >= ABSORB_MS:
                                phase = Phase.DONE
                                finished.emit()
                                queue_free()
                                return
        if phase != Phase.DONE:
                queue_redraw()


func _deliver() -> void:
        delivered = true
        phase = Phase.ABSORB
        t = 0.0
        if receiver != null and is_instance_valid(receiver) \
                        and receiver.has_method("get_pixel_pos"):
                last_receiver_pos = receiver.get_pixel_pos()
        soul_delivered.emit()


func _push_trail() -> void:
        _trail.push_back(soul_pos)
        while _trail.size() > TRAIL_MAX:
                _trail.pop_front()


# ============================================================================
# Rendering (tutto procedurale, coordinate nello spazio dei player)
# ============================================================================
func _draw() -> void:
        match phase:
                Phase.FALL:
                        _draw_body(clampf(t / FALL_MS, 0.0, 1.0), 1.0)
                Phase.RISE:
                        _draw_body(1.0, 0.75)
                        _draw_soul(0.75)
                Phase.FLY:
                        # Il corpo dissolve durante il primo mezzo secondo di volo.
                        var body_a: float = clampf(1.0 - _fly_t / 0.5, 0.0, 1.0) * 0.65
                        if body_a > 0.01:
                                _draw_body(1.0, body_a)
                        _draw_soul(1.0)
                Phase.ABSORB:
                        _draw_absorb(clampf(t / ABSORB_MS, 0.0, 1.0))
                _:
                        pass


# --- Corpo accasciato: la texture della vittima ruota attorno ai piedi -------
# fp = progresso della caduta (0 in piedi → 1 disteso), alpha = dissolvenza.
# TASK 108 (dummy): senza vittima (volo di ritorno voodoo) niente corpo.
func _draw_body(fp: float, alpha: float) -> void:
        if victim == null:
                return
        var pivot: Vector2 = death_pos + Vector2(0.0, 30.0)  # piedi
        # Rotazione accelerata (gravità): da 0 a ~83°, nella direzione in cui
        # guardava la vittima (cade "in avanti").
        var fall_sign: float = -1.0 if body_flip_h else 1.0
        var rot: float = fall_sign * 1.45 * fp * fp
        var mod_color := Color(body_tint.r, body_tint.g, body_tint.b, alpha)
        # Polvere all'impatto (ultimi istanti della caduta).
        if fp > 0.75 and alpha > 0.5:
                var dust_a: float = (1.0 - fp) * 0.55 * alpha
                for i in 6:
                        var ang: float = PI + float(i) / 6.0 * PI * fall_sign
                        var ddist: float = 14.0 + 26.0 * fp
                        draw_circle(pivot + Vector2(cos(ang), -absf(sin(ang)) * 0.35) * ddist,
                                        3.0, Color(0.55, 0.50, 0.45, dust_a))
        if body_tex != null:
                # Specchia orizzontalmente se la vittima guardava a sinistra:
                # draw_texture_rect non ha flip, si usa la scala del transform.
                draw_set_transform(pivot, rot,
                                Vector2(-1.0 if body_flip_h else 1.0, 1.0))
                draw_texture_rect(body_tex, Rect2(-32.0, -62.0, 64.0, 64.0),
                                false, mod_color)
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        else:
                # Fallback (texture non disponibile): sagoma distesa a terra.
                var lie_dir: float = fall_sign
                draw_set_transform(pivot, rot, Vector2.ONE)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(-30.0, -58.0), Vector2(30.0, -58.0),
                        Vector2(30.0, -2.0), Vector2(-30.0, -2.0),
                ]), Color(0.22, 0.20, 0.26, alpha * 0.9))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- L'anima: spiritello luminoso con scia, glow pulsante e codina -----------
func _draw_soul(alpha: float) -> void:
        var pulse: float = 0.85 + 0.15 * sin(_fly_t * 14.0 + float(t) * 0.02)
        # Scia eterea (posizioni precedenti, raggio/alfa decrescenti).
        for i in _trail.size():
                var tp: Vector2 = _trail[i]
                var k: float = float(i + 1) / float(_trail.size())
                draw_circle(tp, 2.0 + 3.5 * k,
                                Color(soul_color.r, soul_color.g, soul_color.b,
                                                0.10 * alpha * k))
        # Glow esterno.
        draw_circle(soul_pos, 15.0 * pulse,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.14 * alpha))
        draw_circle(soul_pos, 9.0,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.35 * alpha))
        # Testa.
        draw_circle(soul_pos + Vector2(0.0, -4.0), 7.5,
                        Color(1.0, 1.0, 1.0, 0.95 * alpha * pulse))
        # Corpo a goccia con codina che ondeggia.
        var wob: float = sin(_fly_t * 18.0 + float(t) * 0.03) * 3.0
        draw_circle(soul_pos + Vector2(wob * 0.4, 2.0), 5.5,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.85 * alpha))
        draw_circle(soul_pos + Vector2(wob, 6.0), 3.5,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.65 * alpha))
        draw_circle(soul_pos + Vector2(wob * 1.4, 9.0), 2.0,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.45 * alpha))
        # Occhi scuri (spiritello stile arcade, non inquietante).
        draw_circle(soul_pos + Vector2(-2.6, -5.0), 1.3, Color(0.10, 0.14, 0.22, 0.9 * alpha))
        draw_circle(soul_pos + Vector2(2.6, -5.0), 1.3, Color(0.10, 0.14, 0.22, 0.9 * alpha))
        # Scintille che salgono attorno all'anima.
        for i in 3:
                var sp: float = sin(float(i) * 2.1 + float(t) * 0.015)
                var spark_pos: Vector2 = soul_pos + Vector2(
                                sp * 12.0, 8.0 - fmod(float(t) * 0.05 + float(i) * 7.0, 18.0))
                draw_circle(spark_pos, 1.2,
                                Color(1.0, 1.0, 1.0, 0.5 * alpha * (0.5 + 0.5 * sp)))


# --- Burst di assorbimento: anelli di ricarica + scintille radiali -----------
func _draw_absorb(ap: float) -> void:
        var center: Vector2 = last_receiver_pos + Vector2(0.0, -14.0)
        var fade: float = 1.0 - ap
        # Anello principale in espansione (l'energia si distribuisce).
        var r1: float = 6.0 + 30.0 * ap
        draw_arc(center, r1, 0.0, TAU, 40,
                        Color(soul_color.r, soul_color.g, soul_color.b, 0.7 * fade), 2.5)
        # Secondo anello ritardato.
        if ap > 0.3:
                var r2: float = 4.0 + 22.0 * (ap - 0.3) / 0.7
                draw_arc(center, r2, 0.0, TAU, 32,
                                Color(1.0, 1.0, 1.0, 0.45 * fade), 1.5)
        # Scintille radiali (8 raggi che si allungano verso l'esterno).
        for i in 8:
                var ang: float = float(i) / 8.0 * TAU + 0.2
                var inner: float = r1 * 0.75
                var outer: float = r1 * 0.75 + 14.0 * ap
                draw_line(center + Vector2(cos(ang), sin(ang)) * inner,
                                center + Vector2(cos(ang), sin(ang)) * outer,
                                Color(1.0, 1.0, 1.0, 0.55 * fade), 1.5)
        # Fulgore centrale morente.
        draw_circle(center, 5.0 * fade + 2.0,
                        Color(1.0, 1.0, 1.0, 0.35 * fade))

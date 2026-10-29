## BossDeathSequences.gd — TASK 86: animazioni di morte per-tipo dei BOSS.
## ============================================================
## Richiesta utente: "quando vengono uccisi, invece di far apparire subito
## le card delle armi bonus, prima il boss viene 'inghiottito' dal suolo:
## dal pavimento si apre una voragine con le fiamme e un vortice lo
## risucchia negli inferi. Per i boss di roccia: sgretolamento della roccia,
## diventano sassolini e scompaiono. Per Dracula: diventa un piccolo
## pipistrello e sparisce con un lampo. (Inventare animazioni coerenti col
## tipo di personaggio, con suoni, animazioni ed effetti ambientali.)"
##
## Il nodo viene creato dal BossRoomController alla morte del boss, guida la
## trasformazione del nodo Boss (sink/shrink/spin/hide) e disegna effetti
## ambientali (voragine, fiamme, vortice, sassolini, pipistrello, monete,
## corvi, ratti...) SOPRA il boss (figlio aggiunto per ultimo). Al termine
## emette `finished` -> il controller prosegue col flusso originale
## (effetti morte + schermata bonus reliquie / vittoria).
##
## Famiglie (17 boss -> 14 sequenze visive):
##   hell    — voragine di fiamme + vortice che risucchia (DEMON, CULT_HERALD)
##   rock    — sgretolamento: il corpo diventa sassolini (GOLEM)
##   ash     — pietrificazione e cenere/braci che salgono (DRAGON)
##   bat     — lampo -> pipistrello che vola via -> lampo (VAMPIRE)
##   soul    — vortice di anime verdi + ossa che crollano (LICH)
##   spectral— dissolvenza eterea in nebbia (WRAITH_LORD, SPECTRAL_ALPHA)
##   goo     — gonfiaggio e burst di droplets (SPIDER, ABOMINATION)
##   ink     — si affloscia in pozza d'inchiostro nero (KRAKEN)
##   arcane  — occhio che si spegne + burst arcano viola (BEHOLDER)
##   rot     — putrefazione in pozza verdognola (GHOUL_LORD)
##   mimic   — si sgonfia + esplosione di monete (COLOSSAL_MIMIC)
##   rats    — il Re esplode in ratti che si disperdono (RAT_KING)
##   crows   — si dissolve in uno stormo di corvi (SUPREME_WITCH)
##   armor   — armatura che cade a pezzi, elmo per ultimo (TWILIGHT_KNIGHT)
extends Node2D
class_name BossDeathSequence

signal finished

const C = preload("res://scripts/core/GameConstants.gd")

# ---- Famiglia per tipo di boss ----
const FAMILY_BY_TYPE := {
        Boss.Type.BOSS_GOLEM: "rock",
        Boss.Type.BOSS_LICH: "soul",
        Boss.Type.BOSS_DEMON: "hell",
        Boss.Type.BOSS_SPIDER: "goo",
        Boss.Type.BOSS_ABOMINATION: "goo",
        Boss.Type.BOSS_KRAKEN: "ink",
        Boss.Type.BOSS_DRAGON: "ash",
        Boss.Type.BOSS_WRAITH_LORD: "spectral",
        Boss.Type.BOSS_VAMPIRE: "bat",
        Boss.Type.BOSS_BEHOLDER: "arcane",
        Boss.Type.BOSS_GHOUL_LORD: "rot",
        Boss.Type.BOSS_SPECTRAL_ALPHA: "spectral",
        Boss.Type.BOSS_CULT_HERALD: "hell",
        Boss.Type.BOSS_COLOSSAL_MIMIC: "mimic",
        Boss.Type.BOSS_RAT_KING: "rats",
        Boss.Type.BOSS_SUPREME_WITCH: "crows",
        Boss.Type.BOSS_TWILIGHT_KNIGHT: "armor",
}

# Palette per famiglia (tint principal, tinte secondarie) e durata.
const FAMILY_SPEC := {
        "hell": {"total": 2800.0, "tint": Color(1.0, 0.45, 0.12)},
        "rock": {"total": 2600.0, "tint": Color(0.62, 0.58, 0.54)},
        "ash": {"total": 2600.0, "tint": Color(1.0, 0.55, 0.2)},
        "bat": {"total": 2500.0, "tint": Color(0.9, 0.05, 0.1)},
        "soul": {"total": 2600.0, "tint": Color(0.35, 1.0, 0.45)},
        "spectral": {"total": 2400.0, "tint": Color(0.5, 0.9, 1.0)},
        "goo": {"total": 2500.0, "tint": Color(0.55, 0.85, 0.3)},
        "ink": {"total": 2600.0, "tint": Color(0.12, 0.1, 0.2)},
        "arcane": {"total": 2600.0, "tint": Color(0.75, 0.4, 1.0)},
        "rot": {"total": 2600.0, "tint": Color(0.45, 0.6, 0.2)},
        "mimic": {"total": 2600.0, "tint": Color(1.0, 0.8, 0.2)},
        "rats": {"total": 2500.0, "tint": Color(0.5, 0.42, 0.35)},
        "crows": {"total": 2600.0, "tint": Color(0.35, 0.2, 0.5)},
        "armor": {"total": 2800.0, "tint": Color(0.45, 0.55, 0.75)},
}

# Boss -> variante colore dentro la famiglia (goo: veleno vs pus, ecc.)
const FAMILY_VARIANT := {
        Boss.Type.BOSS_SPIDER: Color(0.45, 0.3, 0.55),
        Boss.Type.BOSS_ABOMINATION: Color(0.55, 0.75, 0.25),
        Boss.Type.BOSS_WRAITH_LORD: Color(0.45, 1.0, 0.75),
        Boss.Type.BOSS_SPECTRAL_ALPHA: Color(0.4, 0.75, 1.0),
        Boss.Type.BOSS_CULT_HERALD: Color(0.9, 0.35, 0.85),
        Boss.Type.BOSS_DEMON: Color(1.0, 0.45, 0.12),
}

# ---- Stato ----
var boss: Boss = null
var family: String = "hell"
var tint: Color = Color(1.0, 0.45, 0.12)
var total_ms: float = 2800.0
var elapsed_ms: float = 0.0
var _done: bool = false

var boss_base: Vector2 = Vector2.ZERO          # posizione piedi del boss
var pit_center: Vector2 = Vector2.ZERO         # centro effetti a terra
var boss_size: float = 200.0

# RNG deterministico per-cellula di boss (stessa sequenza ogni run di test)
var rng := RandomNumberGenerator.new()

# Particelle generiche {kind,pos,vel,size,color,life,max,rot,vrot,...}
var chunks: Array = []
# Marker sonori gia' sparati (uno per chiave)
var _snd_fired: Dictionary = {}
# Contatori/parametri per-famiglia (stadi, pezzi staccati, actor spawnati)
var _stage: int = 0
var _pieces_released: int = 0
var _actor_spawned: bool = false
# Flash a pieno schermo (colore, alpha decrescente)
var _flash_col: Color = Color(1, 1, 1, 0)
var _flash_ms: float = 0.0
var _flash_total_ms: float = 1.0

# ---- API chiamata dal BossRoomController ----

func begin(b: Boss) -> void:
        boss = b
        family = str(FAMILY_BY_TYPE.get(b.boss_type, "hell"))
        var spec: Dictionary = FAMILY_SPEC.get(family, FAMILY_SPEC["hell"])
        total_ms = float(spec.get("total", 2800.0))
        tint = FAMILY_VARIANT.get(b.boss_type, spec.get("tint", Color(1.0, 0.45, 0.12)))
        boss_base = b.position
        boss_size = maxf(140.0, b.size)
        pit_center = boss_base + Vector2(0.0, boss_size * 0.18)
        rng.seed = int(hash(str("bdeath", b.boss_type, int(b.position.x))))
        z_index = 50
        queue_redraw()


func update(delta_ms: float) -> void:
        if _done:
                return
        if boss == null or not is_instance_valid(boss):
                # Boss sparito (continue/transizione): chiudi subito la
                # sequenza per non congelare il fight all'infinito.
                _done = true
                finished.emit()
                return
        var prev_t: float = elapsed_ms
        elapsed_ms += delta_ms
        if elapsed_ms >= total_ms:
                elapsed_ms = total_ms
        var t: float = elapsed_ms
        var dt: float = delta_ms * 0.001
        # flash overlay
        if _flash_ms > 0.0:
                _flash_ms = maxf(0.0, _flash_ms - delta_ms)
        _family_update(t, prev_t, dt)
        _update_chunks(dt)
        if elapsed_ms >= total_ms:
                _done = true
                if boss != null and is_instance_valid(boss):
                        boss.visible = false
                finished.emit()
        queue_redraw()


# ---- Suoni / shake one-shot ----

func _snd(key: String, type: int) -> void:
        if _snd_fired.has(key):
                return
        _snd_fired[key] = true
        if AudioManager:
                AudioManager.play_sound(type)

func _shake(amount: float, dur: float) -> void:
        if EffectsManager:
                EffectsManager.screen_shake(amount, dur)

# ---- Spawn particelle ----

func _spawn(kind: String, pos: Vector2, vel: Vector2, psize: float,
                color: Color, life_ms: float, extra: Dictionary = {}) -> void:
        chunks.append({
                "kind": kind, "pos": pos, "vel": vel, "size": psize,
                "color": color, "life": life_ms, "max": life_ms,
                "rot": float(extra.get("rot", rng.randf() * TAU)),
                "vrot": float(extra.get("vrot", rng.randf_range(-7.0, 7.0))),
                "floor_y": float(extra.get("floor_y", boss_base.y + boss_size * 0.22)),
                "ang": float(extra.get("ang", rng.randf() * TAU)),
                "vang": float(extra.get("vang", rng.randf_range(2.5, 5.5))),
                "rad": float(extra.get("rad", boss_size * 0.4)),
                "vrad": float(extra.get("vrad", -boss_size * 0.30)),
                "h": float(extra.get("h", 0.0)),
                "vh": float(extra.get("vh", 90.0)),
                "settle": false, "age": 0.0,
                "seed": rng.randf(),
        })

# ============================================================================
# LOGICA PER-FAMIGLIA (update: trasformazioni boss + spawn particelle/suoni)
# ============================================================================

func _family_update(t: float, prev_t: float, dt: float) -> void:
        match family:
                "hell":
                        _upd_hell(t, prev_t)
                "rock":
                        _upd_rock(t, prev_t)
                "ash":
                        _upd_ash(t, prev_t)
                "bat":
                        _upd_bat(t, prev_t)
                "soul":
                        _upd_soul(t, prev_t)
                "spectral":
                        _upd_spectral(t, prev_t)
                "goo":
                        _upd_goo(t, prev_t)
                "ink":
                        _upd_ink(t, prev_t)
                "arcane":
                        _upd_arcane(t, prev_t)
                "rot":
                        _upd_rot(t, prev_t)
                "mimic":
                        _upd_mimic(t, prev_t)
                "rats":
                        _upd_rats(t, prev_t)
                "crows":
                        _upd_crows(t, prev_t)
                "armor":
                        _upd_armor(t, prev_t)


# --- hell: voragine di fiamme + vortice che risucchia negli inferi ---
# 0-700   crepa a spirale che si apre (rumble) + boss trema
# 700-1500 voragine si apre (collapse), fiamme sul bordo, boss comincia a girare
# 1500-2300 risucchio vorticoso: il boss orbita, scala e scende nel buco
# 2300-2800 chiusura con anello di braci + burst finale
func _upd_hell(t: float, prev_t: float) -> void:
        if t < 700.0:
                _snd("hell_crack", AudioManager.SoundType.HAZARD_RUMBLE)
                _shake(2.0, 0.2)
                boss.position = boss_base + Vector2(
                                rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
        elif t < 1500.0:
                _snd("hell_open", AudioManager.SoundType.HAZARD_COLLAPSE)
                _shake(4.0, 0.3)
                var kk: float = (t - 700.0) / 800.0
                boss.rotation = kk * 2.2
                boss.scale = Vector2.ONE
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.18)
                if t - prev_t > 0.0 and int(t / 90.0) != int(prev_t / 90.0):
                        _spawn_flame_rim()
        elif t < 2300.0:
                _snd("hell_suck", AudioManager.SoundType.PORTAL_CLOSE)
                _shake(5.0, 0.35)
                var kk: float = (t - 1500.0) / 800.0
                var spin: float = kk * kk * 26.0
                boss.rotation = 2.2 + spin
                var sc: float = clampf(1.0 - kk * 1.05, 0.0, 1.0)
                boss.scale = Vector2(sc, sc)
                var orb: float = boss_size * 0.35 * (1.0 - kk)
                boss.position = pit_center + Vector2(
                                cos(spin * 0.8) * orb, sin(spin * 1.1) * orb * 0.4) \
                                + Vector2(0.0, kk * boss_size * 0.30)
                boss.modulate = Color(1.0, 0.85, 0.7, 1.0 - 0.35 * kk)
                if kk > 0.92:
                        boss.visible = false
                if int(t / 60.0) != int(prev_t / 60.0):
                        _spawn_fire_spiral()
                        _spawn_flame_rim()
        else:
                _snd("hell_boom", AudioManager.SoundType.BOSS_DEATH)
                if prev_t < 2300.0 and t >= 2300.0:
                        _shake(10.0, 0.5)
                        for i in 26:
                                var a: float = float(i) / 26.0 * TAU
                                var sp: float = rng.randf_range(160.0, 340.0)
                                _spawn("ember", pit_center + Vector2(cos(a), sin(a) * 0.5) * 12.0,
                                                Vector2(cos(a) * sp, sin(a) * 0.5 * sp - 60.0),
                                                rng.randf_range(2.0, 4.5),
                                                Color(1.0, rng.randf_range(0.45, 0.7), 0.1),
                                                rng.randf_range(500.0, 900.0))
                boss.visible = false


func _spawn_flame_rim() -> void:
        var rr: float = boss_size * 0.52
        var a: float = rng.randf() * TAU
        var p: Vector2 = pit_center + Vector2(cos(a), sin(a) * 0.42) * rr
        _spawn("ember", p, Vector2(rng.randf_range(-14.0, 14.0), -rng.randf_range(30.0, 80.0)),
                        rng.randf_range(2.5, 5.0), Color(1.0, rng.randf_range(0.4, 0.75), 0.1),
                        rng.randf_range(350.0, 700.0))


func _spawn_fire_spiral() -> void:
        _spawn("fire_spiral", pit_center, Vector2.ZERO, rng.randf_range(3.0, 5.5),
                        Color(1.0, 0.5, 0.1), 700.0, {"vang": rng.randf_range(3.0, 6.0),
                        "vrad": -boss_size * rng.randf_range(0.35, 0.55),
                        "rad": boss_size * rng.randf_range(0.45, 0.6),
                        "vh": rng.randf_range(50.0, 130.0)})


# --- rock: sgretolamento — il corpo diventa sassolini ---
# 0-500    tremito + crepa (PILLAR_CRACK), polvere alla base
# 500-1600 pezzi si staccano a raffica (WALL_CRUMBLE), il boss scala a gradini
# 1600-2200 collasso finale (PILLAR_COLLAPSE): scala->0, cumulo di sassolini
# 2200-2600 i sassolini lampeggiano e svaniscono in polvere
func _upd_rock(t: float, prev_t: float) -> void:
        var rubble_col: Color = Color(0.5, 0.47, 0.44)
        if t < 500.0:
                _snd("rock_crack", AudioManager.SoundType.PILLAR_CRACK)
                boss.position = boss_base + Vector2(
                                rng.randf_range(-3.0, 3.0), rng.randf_range(-2.0, 2.0))
                if int(t / 110.0) != int(prev_t / 110.0):
                        _spawn("mist", boss_base + Vector2(rng.randf_range(-30.0, 30.0),
                                        boss_size * 0.1), Vector2.ZERO, rng.randf_range(6.0, 10.0),
                                        Color(0.55, 0.52, 0.48, 0.25), 600.0)
        elif t < 1600.0:
                _snd("rock_crumble", AudioManager.SoundType.WALL_CRUMBLE)
                _shake(3.0, 0.15)
                if int(t / 120.0) != int(prev_t / 120.0) and _pieces_released < 9:
                        _pieces_released += 1
                        var side: float = rng.randf_range(-1.0, 1.0)
                        _spawn("rubble", boss_base + Vector2(side * boss_size * 0.30,
                                        -boss_size * rng.randf_range(0.15, 0.55)),
                                        Vector2(side * rng.randf_range(30.0, 110.0),
                                        rng.randf_range(-60.0, -10.0)),
                                        rng.randf_range(4.5, 9.0),
                                        Color(0.5, 0.47, 0.44).darkened(rng.randf_range(0.0, 0.25)),
                                        rng.randf_range(1500.0, 2100.0))
                        _spawn("rubble", boss_base + Vector2(-side * boss_size * 0.34,
                                        -boss_size * rng.randf_range(0.1, 0.45)),
                                        Vector2(-side * rng.randf_range(25.0, 90.0),
                                        rng.randf_range(-40.0, 0.0)),
                                        rng.randf_range(3.5, 8.0), rubble_col.darkened(0.15),
                                        rng.randf_range(1400.0, 2000.0))
                var sc: float = 1.0 - 0.09 * float(_pieces_released)
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(rng.randf_range(-2.0, 2.0), 0.0)
        elif t < 2200.0:
                _snd("rock_collapse", AudioManager.SoundType.PILLAR_COLLAPSE)
                if prev_t < 1600.0:
                        _shake(8.0, 0.45)
                        for i in 16:
                                var side2: float = rng.randf_range(-1.0, 1.0)
                                _spawn("rubble", boss_base + Vector2(side2 * boss_size * 0.25,
                                                -boss_size * rng.randf_range(0.05, 0.4)),
                                                Vector2(side2 * rng.randf_range(40.0, 150.0),
                                                rng.randf_range(-90.0, -20.0)),
                                                rng.randf_range(4.0, 10.0),
                                                rubble_col.darkened(rng.randf_range(0.0, 0.3)),
                                                rng.randf_range(1300.0, 2000.0))
                var kk: float = (t - 1600.0) / 600.0
                var sc2: float = clampf(1.0 - 0.09 * 9.0 - kk * 0.25, 0.0, 1.0)
                boss.scale = Vector2(sc2, sc2)
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.10)
                if kk > 0.85:
                        boss.visible = false
        else:
                _snd("rock_boom", AudioManager.SoundType.BOSS_DEATH)
                if prev_t < 2200.0:
                        for ch in chunks:
                                if ch["kind"] == "rubble":
                                        ch["life"] = minf(float(ch["life"]),
                                                        float(ch["max"]) * 0.35 + 200.0)
                                        ch["vanish_glow"] = true


# --- ash: pietrificazione + sgretolamento in cenere e braci (drago) ---
func _upd_ash(t: float, prev_t: float) -> void:
        if t < 700.0:
                _snd("ash_rumble", AudioManager.SoundType.HAZARD_RUMBLE)
                _shake(2.5, 0.2)
                boss.position = boss_base + Vector2(
                                rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
                boss.modulate = Color(0.75, 0.72, 0.70)  # pietrificazione (tinta grigia)
                if int(t / 100.0) != int(prev_t / 100.0):
                        _spawn("ember", boss_base + Vector2(rng.randf_range(-20.0, 20.0),
                                        -boss_size * 0.4), Vector2(0.0, -rng.randf_range(40.0, 90.0)),
                                        rng.randf_range(2.0, 4.0), Color(1.0, 0.5, 0.15),
                                        rng.randf_range(400.0, 800.0))
        elif t < 1800.0:
                _snd("ash_crumble", AudioManager.SoundType.WALL_CRUMBLE)
                _shake(3.5, 0.15)
                if int(t / 90.0) != int(prev_t / 90.0):
                        var side: float = rng.randf_range(-1.0, 1.0)
                        _spawn("rubble", boss_base + Vector2(side * boss_size * 0.28,
                                        -boss_size * rng.randf_range(0.1, 0.5)),
                                        Vector2(side * rng.randf_range(20.0, 80.0),
                                        rng.randf_range(-50.0, -10.0)),
                                        rng.randf_range(3.0, 6.5), Color(0.42, 0.40, 0.39),
                                        rng.randf_range(1200.0, 1800.0))
                        _spawn("ash", boss_base + Vector2(side * boss_size * 0.2,
                                        -boss_size * rng.randf_range(0.1, 0.5)),
                                        Vector2(side * 20.0, -rng.randf_range(30.0, 70.0)),
                                        rng.randf_range(1.5, 3.0), Color(0.6, 0.58, 0.56),
                                        rng.randf_range(700.0, 1200.0))
                        _spawn("ember", boss_base + Vector2(rng.randf_range(-15.0, 15.0),
                                        -boss_size * rng.randf_range(0.2, 0.55)),
                                        Vector2(0.0, -rng.randf_range(60.0, 120.0)),
                                        rng.randf_range(2.0, 3.5), Color(1.0, 0.55, 0.2),
                                        rng.randf_range(500.0, 900.0))
                var kk: float = (t - 700.0) / 1100.0
                var sc: float = clampf(1.0 - kk * 0.95, 0.0, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.12)
                if kk > 0.9:
                        boss.visible = false
        else:
                _snd("ash_boom", AudioManager.SoundType.BOSS_DEATH)
                if prev_t < 1800.0 and t >= 1800.0:
                        _shake(7.0, 0.4)
                        for i in 30:
                                var a: float = rng.randf() * TAU
                                _spawn("ember", boss_base + Vector2(rng.randf_range(-25.0, 25.0),
                                                -boss_size * 0.15),
                                                Vector2(cos(a) * rng.randf_range(20.0, 90.0),
                                                -rng.randf_range(80.0, 220.0)),
                                                rng.randf_range(1.8, 4.0),
                                                Color(1.0, rng.randf_range(0.4, 0.7), 0.12),
                                                rng.randf_range(600.0, 1100.0))
                boss.visible = false


# --- bat: lampo -> pipistrello che vola via -> lampo (vampiro/Dracula) ---
func _upd_bat(t: float, prev_t: float) -> void:
        if t < 600.0:
                _snd("bat_laugh", AudioManager.SoundType.DARK_LAUGH)
                _flash(Color(1.0, 1.0, 1.0, 0.75), 260.0)
                var kk: float = t / 600.0
                var sc: float = clampf(1.0 - kk * 0.88, 0.12, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(0.0, -kk * boss_size * 0.1)
                boss.rotation = kk * 0.6
                if int(t / 80.0) != int(prev_t / 80.0):
                        _spawn("mist", boss_base + Vector2(rng.randf_range(-18.0, 18.0),
                                        -boss_size * 0.2), Vector2.ZERO, rng.randf_range(4.0, 8.0),
                                        Color(0.15, 0.05, 0.1, 0.4), 500.0)
        elif t < 2000.0:
                if prev_t < 600.0 and t >= 600.0:
                        _snd("bat_screech", AudioManager.SoundType.BAT_SCREECH)
                        _snd("bat_flap", AudioManager.SoundType.BAT_FLAP)
                        boss.visible = false
                        _flash(Color(1.0, 0.95, 1.0, 0.5), 160.0)
                        # nasce il pipistrello: vola via a zig-zag
                        # (psize 12 -> sprite ~36px: ben visibile)
                        _spawn("bat", boss_base + Vector2(0.0, -boss_size * 0.25),
                                        Vector2(240.0, -130.0), 12.0, Color(0.12, 0.08, 0.14),
                                        1450.0, {"floor_y": -99999.0})
                # scia di nebbia scura dietro il pipistrello in volo
                if int(t / 110.0) != int(prev_t / 110.0):
                        for ch in chunks:
                                if ch["kind"] == "bat":
                                        _spawn("mist", ch["pos"] + Vector2(-12.0, 4.0),
                                                        Vector2(-14.0, -6.0), 7.0,
                                                        Color(0.16, 0.08, 0.16, 0.45), 480.0)
                                        break
        else:
                _snd("bat_end", AudioManager.SoundType.DARK_LAUGH)
                if prev_t < 2000.0 and t >= 2000.0:
                        _flash(Color(1.0, 1.0, 1.0, 0.85), 300.0)
                        _shake(6.0, 0.3)
                        # il pipistrello svanisce nel lampo: scintille scure
                        for ch in chunks:
                                if ch["kind"] == "bat":
                                        var bp: Vector2 = ch["pos"]
                                        ch["life"] = 0.0
                                        for i in 14:
                                                var a: float = float(i) / 14.0 * TAU
                                                _spawn("spark", bp, Vector2(cos(a), sin(a)) \
                                                                * rng.randf_range(90.0, 240.0),
                                                                2.0, Color(0.9, 0.85, 1.0, 0.9), 400.0)


# --- soul: vortice di anime verdi + ossa che crollano (lich) ---
func _upd_soul(t: float, prev_t: float) -> void:
        if t < 1600.0:
                _snd("soul_rel", AudioManager.SoundType.SOUL_RELEASE)
                var kk: float = t / 1600.0
                boss.position = boss_base + Vector2(rng.randf_range(-2.0, 2.0), kk * boss_size * 0.05)
                var sc: float = clampf(1.0 - kk * 0.45, 0.5, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.modulate = Color(0.85, 1.0, 0.9, 1.0)
                if int(t / 70.0) != int(prev_t / 70.0):
                        _spawn("soul", boss_base + Vector2(rng.randf_range(-30.0, 30.0),
                                        -boss_size * rng.randf_range(0.2, 0.6)),
                                        Vector2(0.0, -rng.randf_range(40.0, 90.0)),
                                        rng.randf_range(2.5, 5.0), Color(0.4, 1.0, 0.5, 0.85),
                                        rng.randf_range(700.0, 1200.0),
                                        {"vang": rng.randf_range(2.0, 5.0),
                                        "vrad": -60.0, "rad": rng.randf_range(30.0, 70.0)})
        elif t < 2200.0:
                _snd("soul_bones", AudioManager.SoundType.WALL_CRUMBLE)
                if prev_t < 1600.0:
                        _shake(5.0, 0.3)
                        for i in 14:
                                var side: float = rng.randf_range(-1.0, 1.0)
                                _spawn("bone", boss_base + Vector2(side * boss_size * 0.25,
                                                -boss_size * rng.randf_range(0.1, 0.5)),
                                                Vector2(side * rng.randf_range(40.0, 130.0),
                                                rng.randf_range(-70.0, -10.0)),
                                                rng.randf_range(4.0, 8.0),
                                                Color(0.92, 0.9, 0.8), 1400.0)
                        # l'anima definitiva sale rapida con scia
                        _spawn("soul", boss_base + Vector2(0.0, -boss_size * 0.3),
                                        Vector2(0.0, -260.0), 8.0, Color(0.5, 1.0, 0.55, 0.95),
                                        900.0, {"vang": 7.0, "vrad": -90.0, "rad": 40.0})
                var kk: float = (t - 1600.0) / 600.0
                var sc: float = clampf(0.55 - kk * 0.6, 0.0, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.08)
                if kk > 0.8:
                        boss.visible = false
        else:
                _snd("soul_boom", AudioManager.SoundType.BOSS_DEATH)
                boss.visible = false


# --- spectral: dissolvenza eterea in nebbia (wraith, lupo spettrale) ---
func _upd_spectral(t: float, prev_t: float) -> void:
        if t < 1400.0:
                _snd("spec_rel", AudioManager.SoundType.SOUL_RELEASE)
                var kk: float = t / 1400.0
                boss.position = boss_base + Vector2(
                                rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
                var sc: float = clampf(1.0 - kk * 0.35, 0.6, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.modulate = Color(0.85, 0.95, 1.0, 1.0 - 0.3 * kk)
                if int(t / 80.0) != int(prev_t / 80.0):
                        _spawn("soul", boss_base + Vector2(rng.randf_range(-35.0, 35.0),
                                        -boss_size * rng.randf_range(0.1, 0.6)),
                                        Vector2(0.0, -rng.randf_range(30.0, 80.0)),
                                        rng.randf_range(2.0, 4.5),
                                        Color(tint.r, tint.g, tint.b, 0.8),
                                        rng.randf_range(700.0, 1200.0))
        elif t < 2100.0:
                _snd("spec_laugh", AudioManager.SoundType.DARK_LAUGH)
                if prev_t < 1400.0:
                        _flash(Color(tint.r, tint.g, tint.b, 0.35), 300.0)
                        for i in 10:
                                _spawn("mist", boss_base + Vector2(rng.randf_range(-40.0, 40.0),
                                                -boss_size * rng.randf_range(0.1, 0.5)),
                                                Vector2(rng.randf_range(-30.0, 30.0),
                                                -rng.randf_range(10.0, 50.0)),
                                                rng.randf_range(10.0, 20.0),
                                                Color(tint.r, tint.g, tint.b, 0.35), 900.0)
                var kk: float = (t - 1400.0) / 700.0
                var sc: float = clampf(0.65 - kk * 0.7, 0.0, 1.0)
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(0.0, -kk * boss_size * 0.05)
                if kk > 0.75:
                        boss.visible = false
        else:
                _snd("spec_boom", AudioManager.SoundType.BOSS_DEATH)
                boss.visible = false


# --- goo: gonfiaggio e burst di droplets (ragno, abominio) ---
func _upd_goo(t: float, prev_t: float) -> void:
        if t < 600.0:
                _snd("goo_grow", AudioManager.SoundType.BLOOD_SPLAT)
                var kk: float = t / 600.0
                var sc: float = 1.0 + kk * 0.30
                boss.scale = Vector2(sc, sc)
                boss.position = boss_base + Vector2(rng.randf_range(-3.0, 3.0), 0.0)
                boss.modulate = Color(1.0, 1.0 - 0.2 * kk, 1.0 - 0.2 * kk)
        elif t < 1800.0:
                if prev_t < 600.0:
                        _snd("goo_burst", AudioManager.SoundType.ENEMY_EXPLODE)
                        _shake(9.0, 0.4)
                        boss.visible = false
                        for i in 30:
                                var a: float = float(i) / 30.0 * TAU + rng.randf() * 0.2
                                var sp: float = rng.randf_range(120.0, 380.0)
                                _spawn("goo", boss_base + Vector2(0.0, -boss_size * 0.25)
                                                + Vector2(cos(a), sin(a)) * 10.0,
                                                Vector2(cos(a) * sp, sin(a) * sp * 0.6 - 60.0),
                                                rng.randf_range(3.0, 7.0),
                                                tint.darkened(rng.randf_range(0.0, 0.3)),
                                                rng.randf_range(900.0, 1600.0))
                        for i in 6:
                                _spawn("mist", boss_base + Vector2(rng.randf_range(-30.0, 30.0),
                                                -boss_size * 0.2), Vector2(0.0, -40.0),
                                                rng.randf_range(12.0, 22.0),
                                                Color(tint.r, tint.g, tint.b, 0.3), 700.0)
        else:
                _snd("goo_boom", AudioManager.SoundType.BOSS_DEATH)


# --- ink: si affloscia in pozza d'inchiostro nero (kraken) ---
func _upd_ink(t: float, prev_t: float) -> void:
        if t < 900.0:
                _snd("ink_splat", AudioManager.SoundType.WALL_CRUMBLE)
                var kk: float = t / 900.0
                boss.scale = Vector2(1.0 + kk * 0.4, clampf(1.0 - kk * 0.75, 0.25, 1.0))
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.10)
                boss.modulate = Color(0.8, 0.8, 0.9)
        elif t < 2000.0:
                _snd("ink_pool", AudioManager.SoundType.HAZARD_RUMBLE)
                if prev_t < 900.0:
                        _shake(4.0, 0.25)
                        for i in 16:
                                var a: float = rng.randf() * TAU
                                _spawn("goo", boss_base + Vector2(0.0, -boss_size * 0.1)
                                                + Vector2(cos(a), sin(a)) * 8.0,
                                                Vector2(cos(a) * rng.randf_range(60.0, 200.0),
                                                sin(a) * rng.randf_range(20.0, 80.0) - 40.0),
                                                rng.randf_range(2.5, 6.0),
                                                Color(0.08, 0.07, 0.13), 1100.0)
                var kk: float = (t - 900.0) / 1100.0
                var sc: float = clampf(0.25 - kk * 0.25, 0.0, 1.0)
                boss.scale = Vector2(1.4 - kk * 0.4, sc)
                if kk > 0.8:
                        boss.visible = false
        else:
                _snd("ink_boom", AudioManager.SoundType.BOSS_DEATH)
                boss.visible = false


# --- arcane: occhio che si spegne + burst arcano (beholder) ---
func _upd_arcane(t: float, prev_t: float) -> void:
        if t < 800.0:
                _snd("arc_zap", AudioManager.SoundType.LIGHTNING)
                var kk: float = t / 800.0
                boss.position = boss_base + Vector2(rng.randf_range(-2.0, 2.0), 0.0)
                var sc: float = 1.0 + sin(t * 0.02) * 0.06
                boss.scale = Vector2(sc, sc)
                boss.modulate = Color(1.0, 1.0 - 0.25 * kk, 1.0 - 0.25 * kk)
        elif t < 1600.0:
                _snd("arc_charge", AudioManager.SoundType.HAZARD_RUMBLE)
                var kk: float = (t - 800.0) / 800.0
                boss.scale = Vector2(1.0 - kk * 0.3, clampf(1.0 - kk * 0.45, 0.5, 1.0))
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.08)
                if int(t / 70.0) != int(prev_t / 70.0):
                        var a: float = rng.randf() * TAU
                        _spawn("spark", boss_base + Vector2(0.0, -boss_size * 0.25)
                                        + Vector2(cos(a), sin(a)) * boss_size * 0.3,
                                        Vector2(-cos(a) * 90.0, -sin(a) * 90.0),
                                        2.0, Color(0.8, 0.5, 1.0, 0.9), 350.0)
        else:
                if prev_t < 1600.0:
                        _snd("arc_burst", AudioManager.SoundType.ENEMY_EXPLODE)
                        _snd("arc_boom", AudioManager.SoundType.BOSS_DEATH)
                        _shake(9.0, 0.45)
                        _flash(Color(0.8, 0.5, 1.0, 0.6), 320.0)
                        boss.visible = false
                        for i in 34:
                                var a: float = float(i) / 34.0 * TAU
                                var sp: float = rng.randf_range(140.0, 420.0)
                                _spawn("spark", boss_base + Vector2(0.0, -boss_size * 0.25),
                                                Vector2(cos(a) * sp, sin(a) * sp * 0.7 - 40.0),
                                                rng.randf_range(1.5, 3.5),
                                                Color(0.85, 0.55, 1.0, 0.95),
                                                rng.randf_range(500.0, 900.0))
                        for i in 8:
                                _spawn("mist", boss_base + Vector2(rng.randf_range(-40.0, 40.0),
                                                -boss_size * 0.2), Vector2(0.0, -30.0),
                                                rng.randf_range(14.0, 26.0),
                                                Color(0.6, 0.35, 0.9, 0.3), 900.0)


# --- rot: putrefazione in pozza verdognola (ghoul) ---
func _upd_rot(t: float, prev_t: float) -> void:
        if t < 1200.0:
                _snd("rot_splat", AudioManager.SoundType.BLOOD_SPLAT)
                var kk: float = t / 1200.0
                boss.scale = Vector2(1.0 + kk * 0.15, clampf(1.0 - kk * 0.4, 0.55, 1.0))
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.06)
                boss.modulate = Color(1.0 - 0.3 * kk, 1.0 - 0.15 * kk, 0.9)
                if int(t / 90.0) != int(prev_t / 90.0):
                        var side: float = rng.randf_range(-1.0, 1.0)
                        _spawn("worm", boss_base + Vector2(side * boss_size * 0.25,
                                        -boss_size * rng.randf_range(0.1, 0.5)),
                                        Vector2(side * rng.randf_range(10.0, 40.0),
                                        rng.randf_range(20.0, 60.0)),
                                        rng.randf_range(1.5, 3.0),
                                        Color(0.4, 0.55, 0.2), 1000.0)
        elif t < 2000.0:
                _snd("rot_pool", AudioManager.SoundType.HAZARD_RUMBLE)
                if prev_t < 1200.0:
                        _shake(3.0, 0.2)
                        for i in 12:
                                var a: float = rng.randf() * TAU
                                _spawn("goo", boss_base + Vector2(0.0, -boss_size * 0.08),
                                                Vector2(cos(a) * rng.randf_range(50.0, 160.0),
                                                sin(a) * rng.randf_range(20.0, 60.0) - 30.0),
                                                rng.randf_range(2.5, 5.5),
                                                Color(0.35, 0.5, 0.18), 1000.0)
                var kk: float = (t - 1200.0) / 800.0
                boss.scale = Vector2(1.15 - kk * 0.4, clampf(0.6 - kk * 0.6, 0.0, 1.0))
                if kk > 0.7:
                        boss.visible = false
                if int(t / 130.0) != int(prev_t / 130.0):
                        _spawn("soul", boss_base + Vector2(rng.randf_range(-30.0, 30.0),
                                        -10.0), Vector2(0.0, -rng.randf_range(30.0, 70.0)),
                                        rng.randf_range(1.5, 3.0),
                                        Color(0.5, 0.7, 0.25, 0.7), 800.0)
        else:
                _snd("rot_boom", AudioManager.SoundType.BOSS_DEATH)
                boss.visible = false


# --- mimic: si sgonfia + esplosione di monete (mimico colossale) ---
func _upd_mimic(t: float, prev_t: float) -> void:
        if t < 700.0:
                _snd("mim_gulp", AudioManager.SoundType.POTION_GULP)
                var kk: float = t / 700.0
                var wob: float = 1.0 + sin(t * 0.03) * 0.05 * (1.0 - kk)
                boss.scale = Vector2(wob * (1.0 - kk * 0.35), (2.0 - wob) * (1.0 - kk * 0.35))
                boss.position = boss_base + Vector2(0.0, kk * boss_size * 0.05)
        elif t < 2000.0:
                if prev_t < 700.0:
                        _snd("mim_coins", AudioManager.SoundType.TREASURE)
                        _shake(6.0, 0.35)
                        for i in 18:
                                var a: float = -PI * 0.5 + rng.randf_range(-1.1, 1.1)
                                var sp: float = rng.randf_range(180.0, 430.0)
                                _spawn("coin", boss_base + Vector2(rng.randf_range(-15.0, 15.0),
                                                -boss_size * 0.2),
                                                Vector2(cos(a) * sp, sin(a) * sp),
                                                rng.randf_range(3.5, 6.0),
                                                Color(1.0, 0.8, 0.2), 1700.0)
                var kk: float = (t - 700.0) / 1300.0
                boss.scale = Vector2(clampf(0.65 - kk * 0.65, 0.0, 1.0),
                                clampf(0.65 - kk * 0.65, 0.0, 1.0))
                if kk > 0.6:
                        boss.visible = false
        else:
                _snd("mim_boom", AudioManager.SoundType.BOSS_DEATH)
                if prev_t < 2000.0:
                        for ch in chunks:
                                if ch["kind"] == "coin":
                                        ch["life"] = minf(float(ch["life"]), 500.0)


# --- rats: il Re esplode in ratti che si disperdono (re dei ratti) ---
func _upd_rats(t: float, prev_t: float) -> void:
        if t < 600.0:
                _snd("rat_squeak", AudioManager.SoundType.BAT_SCREECH)
                boss.position = boss_base + Vector2(rng.randf_range(-3.0, 3.0), 0.0)
                boss.scale = Vector2.ONE * (1.0 + sin(t * 0.05) * 0.05)
        elif t < 2000.0:
                if prev_t < 600.0:
                        _snd("rat_burst", AudioManager.SoundType.ENEMY_EXPLODE)
                        _shake(5.0, 0.3)
                        boss.visible = false
                        for i in 10:
                                var a: float = float(i) / 10.0 * TAU + rng.randf() * 0.3
                                var dirx: float = cos(a)
                                _spawn("rat", boss_base + Vector2(0.0, -boss_size * 0.1)
                                                + Vector2(cos(a), sin(a)) * 12.0,
                                                Vector2(dirx * rng.randf_range(180.0, 340.0),
                                                sin(a) * rng.randf_range(30.0, 90.0) - 20.0),
                                                rng.randf_range(5.0, 8.0),
                                                Color(0.45, 0.38, 0.32), 1500.0)
        else:
                _snd("rat_laugh", AudioManager.SoundType.DARK_LAUGH)
                _snd("rat_boom", AudioManager.SoundType.BOSS_DEATH)


# --- crows: si dissolve in uno stormo di corvi (strega suprema) ---
func _upd_crows(t: float, prev_t: float) -> void:
        if t < 800.0:
                _snd("cr_laugh", AudioManager.SoundType.DARK_LAUGH)
                var kk: float = t / 800.0
                boss.position = boss_base + Vector2(rng.randf_range(-2.5, 2.5),
                                rng.randf_range(-2.5, 2.5))
                boss.scale = Vector2.ONE * clampf(1.0 - kk * 0.2, 0.8, 1.0)
                boss.modulate = Color(1.0, 0.9, 1.0)
        elif t < 2000.0:
                if prev_t < 800.0:
                        _snd("cr_flap", AudioManager.SoundType.BAT_FLAP)
                        _flash(Color(0.7, 0.4, 1.0, 0.5), 280.0)
                        boss.visible = false
                        for i in 9:
                                var a: float = -PI * 0.5 + rng.randf_range(-1.3, 1.3)
                                var sp: float = rng.randf_range(160.0, 360.0)
                                _spawn("crow", boss_base + Vector2(rng.randf_range(-20.0, 20.0),
                                                -boss_size * 0.25),
                                                Vector2(cos(a) * sp, sin(a) * sp),
                                                rng.randf_range(8.0, 11.0),
                                                Color(0.08, 0.06, 0.12), 1500.0,
                                                {"floor_y": -99999.0})
        else:
                _snd("cr_boom", AudioManager.SoundType.BOSS_DEATH)
                if prev_t < 2000.0:
                        _flash(Color(0.6, 0.35, 0.95, 0.5), 260.0)


# --- armor: armatura che cade a pezzi, elmo per ultimo (cav. crepuscolo) ---
func _upd_armor(t: float, prev_t: float) -> void:
        if t < 600.0:
                _snd("ar_crack", AudioManager.SoundType.PILLAR_CRACK)
                boss.position = boss_base + Vector2(rng.randf_range(-2.5, 2.5), 0.0)
        elif t < 1800.0:
                _snd("ar_clank", AudioManager.SoundType.HAMMER_CLANK)
                if int(t / 170.0) != int(prev_t / 170.0) and _pieces_released < 6:
                        _pieces_released += 1
                        var side: float = rng.randf_range(-1.0, 1.0)
                        _snd("ar_piece%d" % _pieces_released, AudioManager.SoundType.HAMMER_CLANK)
                        _spawn("piece", boss_base + Vector2(side * boss_size * 0.3,
                                        -boss_size * rng.randf_range(0.15, 0.55)),
                                        Vector2(side * rng.randf_range(30.0, 110.0),
                                        rng.randf_range(-40.0, 0.0)),
                                        rng.randf_range(6.0, 11.0),
                                        Color(0.45, 0.55, 0.75), 2000.0)
                        var sc: float = 1.0 - 0.11 * float(_pieces_released)
                        boss.scale = Vector2(sc, sc)
        elif t < 2200.0:
                if prev_t < 1800.0:
                        _snd("ar_helm", AudioManager.SoundType.HAMMER_CLANK)
                        _shake(6.0, 0.3)
                        boss.visible = false
                        _spawn("piece", boss_base + Vector2(0.0, -boss_size * 0.55),
                                        Vector2(rng.randf_range(-30.0, 30.0), -30.0),
                                        13.0, Color(0.5, 0.6, 0.8), 3000.0,
                                        {"helm": true})
        else:
                _snd("ar_boom", AudioManager.SoundType.BOSS_DEATH)


# ---- Flash overlay helper ----

func _flash(col: Color, ms: float) -> void:
        _flash_col = col
        _flash_ms = ms
        _flash_total_ms = maxf(1.0, ms)

# ============================================================================
# PART 3 — FISICA DEI CHUNKS + RENDERING (_draw)
# ============================================================================

const VP_W: int = C.WINDOW_WIDTH
const VP_H: int = C.WINDOW_HEIGHT


func _update_chunks(dt: float) -> void:
        var doomed: Array = []
        for i in chunks.size():
                var ch: Dictionary = chunks[i]
                ch["age"] = float(ch["age"]) + dt
                ch["life"] = float(ch["life"]) - dt * 1000.0
                if float(ch["life"]) <= 0.0:
                        doomed.append(i)
                        continue
                var kind: String = ch["kind"]
                var vel: Vector2 = ch["vel"]
                var pos: Vector2 = ch["pos"]
                match kind:
                        "ember", "ash", "spark":
                                pos += vel * dt
                                vel *= maxf(0.0, 1.0 - 1.8 * dt)
                                if kind == "ember":
                                        vel.y -= 52.0 * dt  # aria calda che sale
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "mist":
                                pos += vel * dt
                                ch["pos"] = pos
                                ch["size"] = float(ch["size"]) + 13.0 * dt
                        "rubble", "bone", "piece":
                                vel.y += 940.0 * dt
                                pos += vel * dt
                                ch["rot"] = float(ch["rot"]) + float(ch["vrot"]) * dt
                                var fy: float = float(ch["floor_y"])
                                if pos.y > fy:
                                        pos.y = fy
                                        if absf(vel.y) > 70.0:
                                                vel = Vector2(vel.x * 0.55, -vel.y * 0.36)
                                                ch["vrot"] = float(ch["vrot"]) * 0.45
                                        else:
                                                vel = Vector2.ZERO
                                                ch["vrot"] = 0.0
                                                ch["settle"] = true
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "goo":
                                vel.y += 860.0 * dt
                                pos += vel * dt
                                var fy_g: float = float(ch["floor_y"])
                                if pos.y > fy_g:
                                        pos.y = fy_g
                                        if absf(vel.y) > 55.0:
                                                vel = Vector2(vel.x * 0.45, -vel.y * 0.22)
                                        else:
                                                vel = Vector2.ZERO
                                                ch["settle"] = true
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "coin":
                                vel.y += 1150.0 * dt
                                pos += vel * dt
                                ch["rot"] = float(ch["rot"]) + float(ch["vrot"]) * dt
                                var fy_c: float = float(ch["floor_y"])
                                if pos.y > fy_c:
                                        pos.y = fy_c
                                        vel = Vector2(vel.x * 0.72, -absf(vel.y) * 0.42)
                                        if absf(vel.y) < 40.0:
                                                vel = Vector2.ZERO
                                                ch["vrot"] = 0.0
                                                ch["settle"] = true
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "soul", "fire_spiral":
                                # vortice: orbita ellittica che si stringe
                                # mentre l'anima/fiamma sale (h).
                                ch["ang"] = float(ch["ang"]) + float(ch["vang"]) * dt
                                ch["rad"] = maxf(0.0, float(ch["rad"]) + float(ch["vrad"]) * dt)
                                ch["h"] = float(ch["h"]) + float(ch["vh"]) * dt
                                var a_o: float = float(ch["ang"])
                                var r_o: float = float(ch["rad"])
                                ch["pos"] = pit_center + Vector2(cos(a_o) * r_o,
                                                sin(a_o) * r_o * 0.45) \
                                                - Vector2(0.0, float(ch["h"]))
                        "bat", "crow":
                                pos += vel * dt
                                # volo a zig-zag (sinusoide verticale)
                                pos.y += sin(float(ch["age"]) * 7.5 \
                                                + float(ch["seed"]) * TAU) * 55.0 * dt
                                vel.x *= (1.0 - 0.12 * dt)
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "rat":
                                vel.y += 900.0 * dt
                                pos += vel * dt
                                var fy_r: float = boss_base.y + boss_size * 0.22
                                if pos.y > fy_r:
                                        pos.y = fy_r
                                        vel.y = 0.0
                                        vel.x *= (1.0 - 0.55 * dt)  # corricola e si ferma
                                ch["pos"] = pos
                                ch["vel"] = vel
                        "worm":
                                pos += vel * dt
                                vel *= (1.0 - 0.8 * dt)
                                ch["pos"] = pos
                                ch["vel"] = vel
        for i in range(doomed.size() - 1, -1, -1):
                chunks.remove_at(doomed[i])


# ============================================================================
# RENDERING
# ============================================================================

# ---- Asset pixel-art (PixelLab, TASK 86) ----
# Sheet 4 frame da 64x64 in assets/sprites/env/bossdeath_<id>_sheet.png.
# Caricamento lazy con fallback procedurale se l'asset manca (il gioco
# resta funzionante anche senza i PNG).
var _fx_tex: Dictionary = {}


func _fx_frame(id: String, idx: int) -> AtlasTexture:
        var key: String = "%s/%d" % [id, idx]
        if _fx_tex.has(key):
                return _fx_tex[key]
        var out: AtlasTexture = null
        var p: String = "res://assets/sprites/env/bossdeath_%s_sheet.png" % id
        # Pattern SpriteManager: Image.load() diretto (bypass import system,
        # funziona anche senza cache .godot/imported).
        var abs_p: String = ProjectSettings.globalize_path(p)
        if FileAccess.file_exists(abs_p):
                var img := Image.new()
                if img.load(abs_p) == OK:
                        var tex := ImageTexture.create_from_image(img)
                        if tex != null:
                                var at := AtlasTexture.new()
                                at.atlas = tex
                                at.region = Rect2(float(idx % 4) * 64.0, 0.0, 64.0, 64.0)
                                out = at
        _fx_tex[key] = out
        return out


func _draw() -> void:
        if boss == null:
                return
        var t: float = elapsed_ms
        # 1) Effetti ambientali a terra (sotto le particelle)
        _draw_ground(t)
        # 2) Particelle
        for ch in chunks:
                _draw_chunk(ch)
        # 3) Flash a pieno schermo (sopra tutto)
        if _flash_ms > 0.0 and _flash_total_ms > 0.0:
                var fade: float = clampf(_flash_ms / _flash_total_ms, 0.0, 1.0)
                draw_rect(Rect2(0.0, 0.0, VP_W, VP_H),
                                Color(_flash_col.r, _flash_col.g, _flash_col.b,
                                                _flash_col.a * fade), true)


# ---- Effetti ambientali per-famiglia (a terra) ----

func _draw_ground(t: float) -> void:
        match family:
                "hell":
                        _draw_hell_ground(t)
                "rock", "rats":
                        _draw_dust_ground(t, Color(0.50, 0.47, 0.44))
                "armor":
                        _draw_dust_ground(t, Color(0.45, 0.55, 0.75))
                "ash":
                        _draw_dust_ground(t, Color(0.40, 0.38, 0.36))
                        _draw_glow_ground(t, Color(1.0, 0.45, 0.12), 0.30)
                "ink":
                        _draw_pool_ground(t, Color(0.05, 0.04, 0.10),
                                        Color(0.30, 0.22, 0.50))
                "rot":
                        _draw_pool_ground(t, Color(0.28, 0.42, 0.12),
                                        Color(0.55, 0.75, 0.25))
                "goo":
                        _draw_pool_ground(t, Color(tint.r * 0.55, tint.g * 0.55,
                                        tint.b * 0.55), tint)
                "soul", "arcane", "spectral", "crows", "bat", "mimic":
                        _draw_rune_ground(t, tint)


# --- hell: crepa → voragine di fiamme + vortice → chiusura ---
func _draw_hell_ground(t: float) -> void:
        if t < 700.0:
                var k: float = t / 700.0
                # crepe radiali che si allungano dal centro
                for i in 5:
                        var a: float = float(i) / 5.0 * TAU + 0.35
                        var ln: float = boss_size * 0.55 * k
                        var wob: float = sin(float(i) * 3.7) * 0.25
                        var p1: Vector2 = pit_center + Vector2(
                                        cos(a + wob * 0.3), sin(a + wob * 0.3) * 0.45) * ln
                        draw_line(pit_center, p1,
                                        Color(0.09, 0.04, 0.03, 0.85 * k), 3.0)
                        draw_circle(p1, 2.5, Color(1.0, 0.4, 0.1, 0.5 * k))
                _ellipse(pit_center, boss_size * 0.45 * k, boss_size * 0.19 * k,
                                Color(0.05, 0.02, 0.02, 0.35 * k))
        elif t < 2300.0:
                var k: float = minf(1.0, (t - 700.0) / 450.0)
                var rx: float = boss_size * 0.55 * k
                var ry: float = rx * 0.42
                # alone incandescente esterno (3 gusci)
                _ellipse(pit_center, rx * 1.50, ry * 1.50, Color(1.0, 0.35, 0.08, 0.10))
                _ellipse(pit_center, rx * 1.25, ry * 1.25, Color(1.0, 0.40, 0.10, 0.16))
                _ellipse(pit_center, rx * 1.08, ry * 1.08, Color(1.0, 0.50, 0.12, 0.22))
                # voragine nera + anello bruciato
                _ellipse(pit_center, rx, ry, Color(0.02, 0.01, 0.01, 0.97))
                _ellipse(pit_center, rx * 0.92, ry * 0.92, Color(0.25, 0.05, 0.02, 0.90))
                # lava interna pulsante
                var pulse: float = 0.5 + 0.5 * sin(t * 0.012)
                _ellipse(pit_center, rx * (0.35 + 0.10 * pulse),
                                ry * (0.35 + 0.10 * pulse),
                                Color(1.0, 0.30 + 0.25 * pulse, 0.05, 0.55 + 0.30 * pulse))
                # vortice: 3 braccia a spirale che ruotano (risucchio)
                var rot: float = -t * 0.0038
                for arm in 3:
                        var pts: PackedVector2Array = PackedVector2Array()
                        var cols: PackedColorArray = PackedColorArray()
                        for s in 13:
                                var ss: float = float(s) / 12.0
                                var aa: float = rot + float(arm) * TAU / 3.0 + ss * 4.2
                                var rr: float = rx * (1.0 - ss * 0.82)
                                pts.append(pit_center + Vector2(cos(aa) * rr,
                                                sin(aa) * rr * 0.42))
                                cols.append(Color(1.0, 0.75 - 0.45 * ss, 0.15,
                                                (1.0 - ss) * 0.85))
                        draw_polygon(pts, cols)
                # fiamme sul bordo: archi lampeggianti
                for i in 9:
                        var fa: float = float(i) / 9.0 * TAU + t * 0.001
                        var flick: float = 0.5 + 0.5 * sin(t * 0.045 + float(i) * 2.1)
                        _arc(pit_center, rx * 1.02, ry * 1.02, fa, fa + 0.38,
                                        3.0 + 4.0 * flick,
                                        Color(1.0, 0.55 + 0.30 * flick, 0.10,
                                                        0.55 + 0.35 * flick))
                # vortice pixel-art (PixelLab): ruota sopra la voragine e
                # 'risucchia' il boss (semi-trasparente: il boss resta
                # visibile mentre sprofonda).
                var vt: AtlasTexture = _fx_frame("vortex", int(t * 0.012) % 4)
                if vt != null:
                        var vsize: float = rx * 2.7
                        draw_set_transform(pit_center, rot * 1.35, Vector2.ONE)
                        draw_texture_rect(vt,
                                        Rect2(-vsize * 0.5, -vsize * 0.52,
                                                        vsize, vsize * 0.96),
                                        false, Color(1.0, 1.0, 1.0, 0.88))
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        else:
                var k: float = (t - 2300.0) / 500.0
                var rx: float = boss_size * 0.55 * (1.0 - k)
                var ry: float = rx * 0.42
                _ellipse(pit_center, rx * 1.4, ry * 1.4,
                                Color(1.0, 0.40, 0.10, 0.16 * (1.0 - k)))
                # vortice pixel-art che si restringe e svanisce insieme
                # alla voragine (nessuno stacco brusco a t=2300)
                var vt2: AtlasTexture = _fx_frame("vortex", int(t * 0.012) % 4)
                if vt2 != null and k < 1.0 and rx > 4.0:
                        var vsize2: float = rx * 2.7
                        draw_set_transform(pit_center, -t * 0.0051, Vector2.ONE)
                        draw_texture_rect(vt2,
                                        Rect2(-vsize2 * 0.5, -vsize2 * 0.52,
                                                        vsize2, vsize2 * 0.96),
                                        false, Color(1.0, 1.0, 1.0, 0.88 * (1.0 - k)))
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                if rx > 1.0:
                        _ellipse(pit_center, rx, ry, Color(0.03, 0.01, 0.01, 0.95))
                        _ellipse(pit_center, rx * 0.5, ry * 0.5,
                                        Color(1.0, 0.35, 0.06, 0.50 * (1.0 - k)))
                # anello di braci residue
                for i in 10:
                        var a: float = float(i) / 10.0 * TAU
                        var p: Vector2 = pit_center + Vector2(cos(a) * boss_size * 0.5,
                                        sin(a) * boss_size * 0.21)
                        draw_circle(p, 2.2, Color(1.0, 0.45, 0.10, 0.50 * (1.0 - k)))


# --- dust: nuvola di polvere alla base (rock, armor, ash, rats) ---
func _draw_dust_ground(t: float, col: Color) -> void:
        var k: float = minf(1.0, t / 900.0)
        var fade: float = 1.0 - clampf((t - 1600.0) / 1000.0, 0.0, 1.0)
        if fade <= 0.0:
                return
        var c: Vector2 = boss_base + Vector2(0.0, boss_size * 0.16)
        _ellipse(c, boss_size * (0.35 + 0.30 * k), boss_size * 0.12 * (0.6 + 0.4 * k),
                        Color(col.r, col.g, col.b, 0.22 * fade))
        _ellipse(c, boss_size * (0.20 + 0.18 * k), boss_size * 0.07 * (0.6 + 0.4 * k),
                        Color(col.r, col.g, col.b, 0.30 * fade))
        # crepe a terra attorno alla base
        for i in 4:
                var a: float = float(i) / 4.0 * TAU + 0.6
                var p1: Vector2 = c + Vector2(cos(a), sin(a) * 0.4) \
                                * boss_size * 0.30 * k
                draw_line(c, p1, Color(0.10, 0.08, 0.07, 0.55 * fade), 2.0)


# --- glow: alone di braci (ash) ---
func _draw_glow_ground(t: float, col: Color, base_alpha: float) -> void:
        var fade: float = 1.0 - clampf((t - 1800.0) / 800.0, 0.0, 1.0)
        if fade <= 0.0:
                return
        var pulse: float = 0.6 + 0.4 * sin(t * 0.010)
        _ellipse(boss_base + Vector2(0.0, boss_size * 0.16),
                        boss_size * 0.45 * pulse, boss_size * 0.16 * pulse,
                        Color(col.r, col.g, col.b, base_alpha * fade * pulse))


# --- pool: pozza che si allarga (ink, rot, goo) ---
func _draw_pool_ground(t: float, col: Color, rim: Color) -> void:
        var k: float = minf(1.0, t / 1400.0)
        var fade: float = 1.0 - clampf((t - 1900.0) / 700.0, 0.0, 1.0)
        if fade <= 0.0:
                return
        var c: Vector2 = boss_base + Vector2(0.0, boss_size * 0.18)
        var rx: float = boss_size * 0.58 * k
        _ellipse(c, rx, rx * 0.30, Color(col.r, col.g, col.b, 0.85 * fade))
        _ellipse(c, rx * 0.72, rx * 0.22, Color(rim.r, rim.g, rim.b, 0.30 * fade))
        # bollle che affiorano
        for i in 5:
                var ph: float = fposmod(t * 0.0011 + float(i) * 0.37, 1.0)
                var a: float = float(i) / 5.0 * TAU + 0.4
                var p: Vector2 = c + Vector2(cos(a), sin(a) * 0.3) * rx * 0.5
                draw_circle(p, 1.5 + 2.5 * ph, Color(rim.r, rim.g, rim.b,
                                0.45 * fade * (1.0 - ph)))


# --- rune: cerchio magico rotante (soul, arcane, spectral, bat, crows, mimic) ---
func _draw_rune_ground(t: float, col: Color) -> void:
        var k: float = minf(1.0, t / 500.0)
        var fade: float = 1.0 - clampf((t - 1800.0) / 800.0, 0.0, 1.0)
        if fade <= 0.0:
                return
        var rr: float = boss_size * 0.50 * k
        _arc(pit_center, rr, rr * 0.42, 0.0, TAU, 2.0,
                        Color(col.r, col.g, col.b, 0.50 * fade))
        _arc(pit_center, rr * 0.72, rr * 0.30, 0.0, TAU, 1.5,
                        Color(col.r, col.g, col.b, 0.30 * fade))
        # tacche runiche rotanti
        var rot: float = t * 0.0016
        for i in 8:
                var a: float = rot + float(i) / 8.0 * TAU
                var p0: Vector2 = pit_center + Vector2(cos(a) * rr * 0.75,
                                sin(a) * rr * 0.31)
                var p1: Vector2 = pit_center + Vector2(cos(a) * rr, sin(a) * rr * 0.42)
                draw_line(p0, p1, Color(col.r, col.g, col.b, 0.45 * fade), 2.0)
        _ellipse(pit_center, rr * 0.45, rr * 0.19,
                        Color(col.r, col.g, col.b, 0.15 * fade))


# ---- Rendering delle particelle ----

func _draw_chunk(ch: Dictionary) -> void:
        var kind: String = ch["kind"]
        var f: float = clampf(float(ch["life"]) / float(ch["max"]), 0.0, 1.0)
        var pos: Vector2 = ch["pos"]
        var psize: float = float(ch["size"])
        var col: Color = ch["color"]
        var age: float = float(ch["age"])
        match kind:
                "ember":
                        draw_circle(pos, psize * (0.55 + 0.45 * f),
                                        Color(1.0, 0.95, 0.75, f * 0.9))
                        draw_circle(pos, psize * (0.30 + 0.30 * f),
                                        Color(col.r, col.g, col.b, clampf(f * 1.2, 0.0, 1.0)))
                "ash":
                        draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                        draw_rect(Rect2(-psize * 0.5, -psize * 0.35, psize, psize * 0.7),
                                        Color(col.r, col.g, col.b, f))
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                "mist":
                        draw_circle(pos, psize, Color(col.r, col.g, col.b, col.a * f * 0.60))
                        draw_circle(pos, psize * 0.6, Color(col.r, col.g, col.b, col.a * f * 0.50))
                "spark":
                        var d: Vector2 = ch["vel"]
                        if d.length_squared() < 1.0:
                                d = Vector2(1.0, 0.0)
                        d = d.normalized() * (psize * 2.2)
                        draw_line(pos - d * 0.5, pos + d * 0.5,
                                        Color(col.r, col.g, col.b, f), 1.6)
                        draw_circle(pos, psize * 0.5, Color(1.0, 1.0, 0.95, f))
                "rubble":
                        if ch.get("vanish_glow", false):
                                draw_circle(pos, psize * 1.6, Color(1.0, 0.55, 0.20, f * 0.30))
                        var rt: AtlasTexture = _fx_frame("rubble",
                                        int(float(ch["seed"]) * 4.0) % 4)
                        if rt != null:
                                # sassolino pixel-art (variante per seed)
                                draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                                var rs: float = psize * 2.6
                                draw_texture_rect(rt,
                                                Rect2(-rs * 0.5, -rs * 0.5, rs, rs),
                                                false, Color(1.0, 1.0, 1.0, f))
                                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                        else:
                                draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                                var poly: PackedVector2Array = _rock_poly(psize, float(ch["seed"]))
                                var rc: Color = Color(col.r, col.g, col.b, f)
                                draw_colored_polygon(poly, rc)
                                draw_polyline(_close_poly(poly), rc.darkened(0.40), 1.0)
                                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                "bone":
                        var bt: AtlasTexture = _fx_frame("bones",
                                        int(float(ch["seed"]) * 4.0) % 4)
                        if bt != null:
                                # osso pixel-art (variante per seed)
                                draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                                var bs: float = psize * 2.6
                                draw_texture_rect(bt,
                                                Rect2(-bs * 0.5, -bs * 0.5, bs, bs),
                                                false, Color(1.0, 1.0, 1.0, f))
                                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                        else:
                                draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                                var bc: Color = Color(col.r, col.g, col.b, f)
                                draw_rect(Rect2(-psize * 0.5, -psize * 0.16, psize, psize * 0.32), bc)
                                draw_circle(Vector2(-psize * 0.5, 0.0), psize * 0.24, bc)
                                draw_circle(Vector2(psize * 0.5, 0.0), psize * 0.24, bc)
                                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                "goo":
                        if ch["settle"]:
                                _ellipse(pos, psize * 1.6, psize * 0.55,
                                                Color(col.r, col.g, col.b, f * 0.80))
                        else:
                                var sq: float = clampf(absf((ch["vel"] as Vector2).y) / 300.0, 0.0, 1.0)
                                _ellipse(pos, psize * (1.0 - 0.25 * sq),
                                                psize * (1.0 + 0.45 * sq),
                                                Color(col.r, col.g, col.b, f))
                "coin":
                        var sx: float = absf(cos(float(ch["rot"])))
                        if sx < 0.15:
                                # moneta di taglio (lamina)
                                draw_line(pos - Vector2(0.0, psize),
                                                pos + Vector2(0.0, psize),
                                                Color(1.0, 0.85, 0.30, f), 2.0)
                        else:
                                _ellipse(pos, psize * (0.35 + 0.65 * sx), psize,
                                                Color(1.0, 0.78, 0.15, f))
                                _ellipse(pos, psize * (0.35 + 0.65 * sx) * 0.62,
                                                psize * 0.62, Color(1.0, 0.92, 0.45, f))
                "soul":
                        var sa: float = f * 0.9
                        draw_circle(pos, psize, Color(col.r, col.g, col.b, sa * 0.35))
                        draw_circle(pos, psize * 0.55, Color(col.r, col.g, col.b, sa))
                        draw_circle(pos, psize * 0.25, Color(1.0, 1.0, 1.0, sa * 0.70))
                "fire_spiral":
                        # scia di fiamma lungo l'orbita (3 passi indietro)
                        var vv: float = float(ch["vang"])
                        var sgn: float = 1.0 if vv >= 0.0 else -1.0
                        for k2 in 3:
                                var back: float = float(k2) * 0.22
                                var aa: float = float(ch["ang"]) - back * sgn
                                var rr2: float = float(ch["rad"]) + back * psize * 0.9
                                var hh: float = maxf(0.0, float(ch["h"]) - back * 14.0)
                                var pp: Vector2 = pit_center + Vector2(cos(aa) * rr2,
                                                sin(aa) * rr2 * 0.45) - Vector2(0.0, hh)
                                draw_circle(pp, psize * (1.0 - 0.25 * float(k2)),
                                                Color(1.0, 0.70 - 0.20 * float(k2), 0.12,
                                                                f * (1.0 - 0.28 * float(k2))))
                        draw_circle(pos, psize * 1.1, Color(1.0, 0.95, 0.60, f))
                "bat":
                        _draw_bat_actor(pos, psize, age, f, col, false)
                "crow":
                        _draw_bat_actor(pos, psize, age, f, col, true)
                "rat":
                        _draw_rat(pos, psize, age, f, col, ch)
                "piece":
                        draw_set_transform(pos, float(ch["rot"]), Vector2.ONE)
                        if ch.get("helm", false):
                                # elmo: cupola con fessura
                                _arc(Vector2.ZERO, psize, psize, -PI, 0.0, 3.0,
                                                Color(0.55, 0.65, 0.85, f))
                                draw_line(Vector2(-psize * 0.55, 0.0),
                                                Vector2(psize * 0.55, 0.0),
                                                Color(0.10, 0.10, 0.14, f), 2.5)
                        else:
                                # placca metallica con rivetti
                                draw_rect(Rect2(-psize * 0.5, -psize * 0.35,
                                                psize, psize * 0.7),
                                                Color(col.r, col.g, col.b, f))
                                draw_rect(Rect2(-psize * 0.5, -psize * 0.35,
                                                psize, psize * 0.30),
                                                Color(col.r + 0.15, col.g + 0.15,
                                                                col.b + 0.15, f))
                                draw_circle(Vector2(-psize * 0.3, psize * 0.15), 1.2,
                                                Color(0.25, 0.30, 0.40, f))
                                draw_circle(Vector2(psize * 0.3, psize * 0.15), 1.2,
                                                Color(0.25, 0.30, 0.40, f))
                        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                "worm":
                        var wc: Color = Color(col.r, col.g, col.b, f)
                        for s in 4:
                                var off: float = float(s) * psize * 0.55
                                var wy: float = sin(age * 9.0 + float(s) * 1.3) * psize * 0.30
                                draw_circle(pos + Vector2(-off, wy),
                                                psize * (0.55 - 0.08 * float(s)), wc)


# --- attore volante: pipistrello (vampiro) / corvo (strega) ---
func _draw_bat_actor(pos: Vector2, psize: float, age: float, f: float,
                col: Color, crow: bool) -> void:
        # sprite pixel-art (PixelLab): ciclo flap per età (ali desincronizzate
        # tra esemplari); fallback procedurale se l'asset manca.
        var id: String = "crow" if crow else "bat"
        var fps: float = 11.0 if crow else 14.0
        var ft: AtlasTexture = _fx_frame(id, int(age * fps) % 4)
        if ft != null:
                var s: float = psize * (3.4 if crow else 3.0)
                draw_texture_rect(ft, Rect2(pos.x - s * 0.5, pos.y - s * 0.5, s, s),
                                false, Color(1.0, 1.0, 1.0, f))
                return
        var flap: float = sin(age * (11.0 if crow else 15.0))
        var body: Color = Color(col.r, col.g, col.b, f)
        draw_set_transform(pos, 0.0, Vector2.ONE)
        # ali (triangoli che sbattono)
        var span: float = psize * (2.1 if crow else 1.6)
        var wing_up: float = -psize * (1.1 if crow else 0.9) * flap - 1.0
        var wing_l: PackedVector2Array = PackedVector2Array([
                        Vector2(-1.0, 0.0),
                        Vector2(-span, wing_up),
                        Vector2(-span * 0.55, wing_up * 0.35 - psize * 0.15)])
        var wing_r: PackedVector2Array = PackedVector2Array([
                        Vector2(1.0, 0.0),
                        Vector2(span, wing_up),
                        Vector2(span * 0.55, wing_up * 0.35 - psize * 0.15)])
        draw_colored_polygon(wing_l, body)
        draw_colored_polygon(wing_r, body)
        # corpo
        draw_circle(Vector2.ZERO, psize * (0.72 if crow else 0.62), body)
        if crow:
                # becco + coda a ventaglio
                draw_colored_polygon(PackedVector2Array([
                                Vector2(psize * 0.55, -1.0),
                                Vector2(psize * 1.15, 0.5),
                                Vector2(psize * 0.55, 1.5)]),
                                Color(0.95, 0.65, 0.15, f))
                draw_colored_polygon(PackedVector2Array([
                                Vector2(-psize * 0.5, 0.0),
                                Vector2(-psize * 1.3, psize * 0.30),
                                Vector2(-psize * 0.5, psize * 0.45)]),
                                body.darkened(0.2))
        else:
                # orecchie
                draw_colored_polygon(PackedVector2Array([
                                Vector2(-psize * 0.35, -psize * 0.45),
                                Vector2(-psize * 0.15, -psize * 0.95),
                                Vector2(-psize * 0.05, -psize * 0.40)]), body)
                draw_colored_polygon(PackedVector2Array([
                                Vector2(psize * 0.35, -psize * 0.45),
                                Vector2(psize * 0.15, -psize * 0.95),
                                Vector2(psize * 0.05, -psize * 0.40)]), body)
        # occhietti rosso sangue
        draw_circle(Vector2(-psize * 0.22, -psize * 0.12), 1.1, Color(1.0, 0.08, 0.08, f))
        draw_circle(Vector2(psize * 0.22, -psize * 0.12), 1.1, Color(1.0, 0.08, 0.08, f))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- ratto che scappa (re dei ratti) ---
func _draw_rat(pos: Vector2, psize: float, age: float, f: float,
                col: Color, ch: Dictionary) -> void:
        var vel: Vector2 = ch["vel"]
        var dirx: float = 1.0 if vel.x >= 0.0 else -1.0
        var rc: Color = Color(col.r, col.g, col.b, f)
        draw_set_transform(pos, 0.0, Vector2.ONE)
        # coda sinusoide
        var tail: PackedVector2Array = PackedVector2Array()
        for s in 5:
                var tx: float = -dirx * (psize * 0.8 + float(s) * psize * 0.35)
                var ty: float = sin(age * 13.0 - float(s) * 0.9) * psize * 0.22
                tail.append(Vector2(tx, ty))
        draw_polyline(tail, rc.darkened(0.25), 1.6)
        # corpo
        _ellipse(Vector2.ZERO, psize * 0.95, psize * 0.55, rc)
        # testa
        draw_circle(Vector2(dirx * psize * 0.85, -1.0), psize * 0.45, rc)
        # orecchie
        draw_circle(Vector2(dirx * psize * 0.75, -psize * 0.38), psize * 0.18,
                        rc.lightened(0.15))
        draw_circle(Vector2(dirx * psize * 1.0, -psize * 0.32), psize * 0.15,
                        rc.lightened(0.15))
        # occhietti
        draw_circle(Vector2(dirx * psize * 1.0, -psize * 0.05), 0.9,
                        Color(1.0, 0.15, 0.10, f))
        # zampette
        draw_line(Vector2(-psize * 0.4, psize * 0.5),
                        Vector2(-psize * 0.4 + dirx * psize * 0.25 * sin(age * 22.0),
                                        psize * 0.75), rc.darkened(0.3), 1.4)
        draw_line(Vector2(psize * 0.3, psize * 0.5),
                        Vector2(psize * 0.3 + dirx * psize * 0.25 * sin(age * 22.0 + 2.0),
                                        psize * 0.75), rc.darkened(0.3), 1.4)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- Primitive helpers ----

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
        if rx <= 0.5 or ry <= 0.5:
                return
        var pts: PackedVector2Array = PackedVector2Array()
        var n: int = 26
        for i in n:
                var a: float = float(i) / float(n) * TAU
                pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
        draw_colored_polygon(pts, col)


func _arc(c: Vector2, rx: float, ry: float, a0: float, a1: float,
                w: float, col: Color) -> void:
        var n: int = maxi(4, int(ceil(absf(a1 - a0) / 0.35)))
        var pts: PackedVector2Array = PackedVector2Array()
        for i in n:
                var a: float = a0 + (a1 - a0) * float(i) / float(n - 1)
                pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
        draw_polyline(pts, col, w)


func _rock_poly(size: float, seedv: float) -> PackedVector2Array:
        var pts: PackedVector2Array = PackedVector2Array()
        for i in 6:
                var a: float = float(i) / 6.0 * TAU
                var r: float = size * (0.72 + 0.34 * absf(sin(seedv * 37.7 + float(i) * 2.399)))
                pts.append(Vector2(cos(a) * r, sin(a) * r))
        return pts


func _close_poly(poly: PackedVector2Array) -> PackedVector2Array:
        var out: PackedVector2Array = PackedVector2Array(poly)
        if out.size() > 0:
                out.append(out[0])
        return out


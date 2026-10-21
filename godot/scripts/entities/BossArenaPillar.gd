## BossArenaPillar.gd — TASK 39 (L'Arena del Boss) / TASK 42 restyle gotico.
##
## PILASTRO-GUGLIA GOTICO ELEMENTALE: 4 pinnacoli-condotto a tema dell'elemento
## DEBOLE del boss, disposti nell'arena. Meccanica (INVARIATA dal Task 39):
##   * il player (proiettili e fendenti reliquia) li frantuma in 3 colpi:
##     a ogni colpo compaiono crepe LUMINESCENTI (il condotto elementale
##     traspare dalle fratture) + schegge mancanti + flash + scintille
##   * i PROIETTILI DEL BOSS vengono BLOCCATI (consumati) e infliggono 1
##     danno al pilastro: la copertura si consuma durante lo scontro
##   * al crollo: scricchiolio, polvere, la guglia si abbatte e spawna 5
##     frammenti (ArenaDebris) lanciati a raggiera che danneggiano il boss
##   * sul fondo resta un cumulo di macerie gotiche (feedback permanente)
##
## GRAFICA (TASK 42 — polycromia gotica, zero asset esterni):
##   * PLINTO a due gradini smussati con SCOTIA viola in ombra, TORO in
##     bronzo VERDE ossidato con fibbie dorate e GRINFIE (foglie-artiglio)
##     agli angoli
##   * FUSTO A FASCIO: nucleo in pietra calcarea fredda a 3 facce con VENE
##     DI MARMO deterministiche e CORSI di arenaria calda + 2 COLONNINE
##     addossate con anelli dorati e muschio
##   * BANDA A TRAFORO (blind tracery): 3 ARCHI A OGIVA con rosoni in VETRO
##     COLORATO elementale che PULSANO, montanti in oro
##   * CAPITELLO a CROCKETS (foglie rigide in bronzo con punte dorate),
##     astragalo aureo e abaco con intarsio
##   * GUGLIA ottagonale a 3 facce con crockets dorati sui bordi e POMO
##     aureo con croce fiorita finiale
##   * crepe a zigzag con BAGLIORE elementale interno, micro-shake al
##     colpo, tremolio e polvere al crollo
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const DebrisClass = preload("res://scripts/entities/ArenaDebris.gd")

enum PillarState { STANDING, COLLAPSING, RUBBLE }

const SHAKE_MS: float = 140.0
const COLLAPSE_MS: float = 430.0
const PILLAR_W: float = 54.0
const PILLAR_H: float = 130.0

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


# Frammenti lanciati a raggiera (il controller li registra nel gruppo
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
# Palette gotica polycroma (derivata dall'elemento per il vetro/il bagliore)
# ============================================================================

func _gothic_palette() -> Dictionary:
        var el: Color = _pal.get("color", Color.WHITE)
        var glow: Color = _pal.get("glow", Color.WHITE)
        # arenaria calda con un velo dell'elemento (legge il tema a colpo d'occhio)
        var sand: Color = Color(0.66, 0.57, 0.43).lerp(el, 0.10)
        return {
                "lime": Color(0.52, 0.54, 0.60),          # calcarea fredda
                "lime_light": Color(0.68, 0.70, 0.76),
                "lime_dark": Color(0.34, 0.36, 0.43),
                "sand": sand,                               # arenaria calda
                "sand_dark": sand.darkened(0.30),
                "sand_light": sand.lightened(0.18),
                "marble": Color(0.35, 0.36, 0.46),          # vene di marmo violacee
                "verdigris": Color(0.33, 0.53, 0.43),       # bronzo ossidato
                "verdigris_dark": Color(0.22, 0.38, 0.30),
                "gold": Color(0.86, 0.69, 0.28),            # oro antico
                "gold_light": Color(1.00, 0.90, 0.58),
                "gold_dark": Color(0.60, 0.45, 0.16),
                "violet": Color(0.27, 0.23, 0.33),          # ombre di scotia/traforo
                "moss": Color(0.33, 0.45, 0.30),            # muschio
                "el": el,
                "glow": glow,
        }


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
        var gp: Dictionary = _gothic_palette()
        var lime: Color = gp.lime
        var lime_light: Color = gp.lime_light
        var lime_dark: Color = gp.lime_dark
        var sand: Color = gp.sand
        var sand_dark: Color = gp.sand_dark
        var sand_light: Color = gp.sand_light
        var marble: Color = gp.marble
        var verd: Color = gp.verdigris
        var verd_dark: Color = gp.verdigris_dark
        var gold: Color = gp.gold
        var gold_light: Color = gp.gold_light
        var gold_dark: Color = gp.gold_dark
        var violet: Color = gp.violet
        var moss: Color = gp.moss
        var el: Color = gp.el
        var glow: Color = gp.glow

        # micro-shake mentre lampeggia il colpo subito
        var shake_x: float = 0.0
        if _hit_flash_ms > 0.0:
                shake_x = sin(_t * 90.0) * 2.2 * (_hit_flash_ms / SHAKE_MS)
        var ox: float = shake_x
        var top: float = -PILLAR_H * 0.5
        var bottom: float = PILLAR_H * 0.5

        # geometria verticale (dal basso verso l'alto)
        var plinth_lo_y: float = bottom - 14.0          # 51..65
        var plinth_hi_y: float = bottom - 24.0          # 41..51
        var scotia_y: float = bottom - 29.0             # 36..41 (in ombra)
        var torus_y: float = bottom - 34.0              # 31..36 (anello bronzo)
        var shaft_bot: float = torus_y - 2.0            # ~29
        var shaft_top: float = top + 37.0               # ~-28
        var band_bot: float = 14.0
        var band_top: float = -8.0
        var astragal_y: float = shaft_top - 2.0         # collare aureo
        var bell_bot: float = shaft_top - 2.0
        var bell_top: float = top + 23.0                # ~-42
        var abacus_top: float = top + 17.0              # ~-48
        var spire_base: float = abacus_top
        var spire_apex: float = top + 7.0               # ~-58
        var finial_y: float = top + 4.0                 # pomo aureo ~-61

        var core_w: float = 26.0
        var core_half: float = core_w * 0.5
        var pulse: float = 0.55 + 0.45 * sin(_t * 2.6 + _seed)

        # --- 0) ombra a terra ---
        draw_circle(Vector2(0.0, bottom - 4.0), PILLAR_W * 0.62,
                        Color(0.0, 0.0, 0.0, 0.30))

        # --- 1) PLINTO a due gradini smussati + scotia + toro bronzeo ---
        _chamfer_block(Vector2(ox, (plinth_lo_y + bottom) * 0.5),
                        PILLAR_W, 14.0, 5.0, lime, lime_light, lime_dark)
        _chamfer_block(Vector2(ox, (plinth_hi_y + plinth_lo_y) * 0.5),
                        PILLAR_W * 0.84, 10.0, 4.0, lime, lime_light, lime_dark)
        # scotia: profilo concavo in penombra viola
        draw_rect(Rect2(ox - PILLAR_W * 0.36, scotia_y,
                        PILLAR_W * 0.72, 5.0), violet, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.36, scotia_y,
                        PILLAR_W * 0.72, 1.4), lime_dark, true)
        # toro bronzeo ossidato con fibbie dorate
        draw_rect(Rect2(ox - PILLAR_W * 0.38, torus_y,
                        PILLAR_W * 0.76, 5.0), verd, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.38, torus_y,
                        PILLAR_W * 0.76, 1.2), verd.lightened(0.25), true)
        draw_rect(Rect2(ox - PILLAR_W * 0.38, torus_y + 3.8,
                        PILLAR_W * 0.76, 1.2), verd_dark, true)
        for s_i in 3:
                var stud_x: float = ox - PILLAR_W * 0.24 + PILLAR_W * 0.24 * float(s_i)
                draw_rect(Rect2(stud_x - 1.1, torus_y - 0.6, 2.2, 6.2), gold_dark, true)
                draw_rect(Rect2(stud_x - 0.7, torus_y - 0.2, 1.4, 3.0), gold, true)
        # grinfie: foglie-artiglio agli angoli del gradino superiore
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                var claw := PackedVector2Array([
                        Vector2(ox + sgn * PILLAR_W * 0.40, plinth_hi_y - 1.0),
                        Vector2(ox + sgn * (PILLAR_W * 0.40 + 6.5), plinth_hi_y + 4.5),
                        Vector2(ox + sgn * (PILLAR_W * 0.40 + 3.2), plinth_hi_y + 8.0),
                        Vector2(ox + sgn * PILLAR_W * 0.38, plinth_hi_y + 6.5),
                ])
                draw_colored_polygon(claw, verd_dark)
                draw_polyline(claw, gold_dark, 0.9)

        # --- 2) FUSTO A FASCIO: nucleo calcareo a 3 facce + colonnine ---
        var shaft_h: float = shaft_bot - shaft_top
        # faccia sinistra (luce), centrale (media), destra (ombra)
        draw_rect(Rect2(ox - core_half, shaft_top, core_w * 0.38, shaft_h),
                        lime_light, true)
        draw_rect(Rect2(ox - core_half + core_w * 0.38, shaft_top,
                        core_w * 0.30, shaft_h), lime, true)
        draw_rect(Rect2(ox - core_half + core_w * 0.68, shaft_top,
                        core_w * 0.32, shaft_h), lime_dark, true)
        # giunti dei blocchi (corsi sottili in ombra)
        for j_i in 4:
                var jy: float = shaft_top + shaft_h * (0.18 + 0.20 * float(j_i))
                if jy > band_top - 2.0 and jy < band_bot + 2.0:
                        continue  # non attraversare il pannello a traforo
                draw_rect(Rect2(ox - core_half, jy, core_w, 1.1),
                                lime_dark.darkened(0.2), true)
        # corsi di arenaria calda (polycromia)
        draw_rect(Rect2(ox - core_half, 18.0, core_w, 4.2), sand, true)
        draw_rect(Rect2(ox - core_half, 18.0, core_w, 1.1), sand_light, true)
        draw_rect(Rect2(ox - core_half, 21.1, core_w, 1.1), sand_dark, true)
        draw_rect(Rect2(ox - core_half, shaft_top + 3.0, core_w, 3.6), sand, true)
        draw_rect(Rect2(ox - core_half, shaft_top + 3.0, core_w, 1.0), sand_light, true)
        # vene di marmo deterministiche
        for v_i in 3:
                var vpts := PackedVector2Array()
                var v_side: float = -1.0 if v_i % 2 == 0 else 1.0
                for i in 6:
                        var vx: float = ox + v_side * (3.0 + 7.5 * absf(sin(
                                        _seed * 1.7 + float(i) * 1.3 + float(v_i) * 2.4)))
                        var vy: float = shaft_top + 4.0 + float(v_i) * 16.0 \
                                        + float(i) * 5.2 + 3.0 * sin(_seed + float(i))
                        if vy > band_top - 1.0 and vy < band_bot + 1.0:
                                vx = ox  # attraversa il traforo in asse
                        vpts.append(Vector2(vx, vy))
                draw_polyline(vpts, marble, 1.0)
        # colonnine addossate con anelli dorati
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                var colx: float = ox + sgn * 16.5
                draw_rect(Rect2(colx - 2.6, shaft_top + 4.0, 5.2,
                                shaft_h - 6.0), sand.lightened(0.06), true)
                draw_rect(Rect2(colx - 2.6, shaft_top + 4.0, 1.6,
                                shaft_h - 6.0), sand_light, true)
                draw_rect(Rect2(colx + 1.0, shaft_top + 4.0, 1.6,
                                shaft_h - 6.0), sand_dark, true)
                # basi e capitelli delle colonnine (anelli aurei)
                draw_rect(Rect2(colx - 3.3, shaft_bot - 5.0, 6.6, 3.0), gold_dark, true)
                draw_rect(Rect2(colx - 3.3, shaft_top + 1.0, 6.6, 3.0), gold_dark, true)
                draw_rect(Rect2(colx - 2.9, shaft_bot - 4.4, 5.8, 1.2), gold, true)
                draw_rect(Rect2(colx - 2.9, shaft_top + 1.6, 5.8, 1.2), gold, true)
        # muschio sul lato in ombra (deterministico)
        for m_i in 6:
                var hx: float = sin(_seed * 3.3 + float(m_i) * 2.19)
                var hy: float = cos(_seed * 2.1 + float(m_i) * 1.37)
                draw_circle(Vector2(ox - 10.0 + 4.0 * hx, 20.0 + 7.0 * hy),
                                1.3, Color(moss.r, moss.g, moss.b, 0.8))

        # --- 3) BANDA A TRAFORO: 3 archi a ogiva con rosoni in vetro elementale ---
        var band_w: float = PILLAR_W * 0.78
        draw_rect(Rect2(ox - band_w * 0.5, band_top, band_w,
                        band_bot - band_top), violet, true)
        draw_rect(Rect2(ox - band_w * 0.5, band_top, band_w, 1.6),
                        violet.darkened(0.3), true)
        draw_rect(Rect2(ox - band_w * 0.5, band_bot - 1.6, band_w, 1.6),
                        violet.darkened(0.3), true)
        var band_c: float = (band_top + band_bot) * 0.5
        for a_i in 3:
                var ax: float = ox - 11.0 + 11.0 * float(a_i)
                # archetto a ogiva in oro
                var ogive := PackedVector2Array([
                        Vector2(ax - 4.6, band_bot - 1.5),
                        Vector2(ax - 4.6, band_top + 6.0),
                        Vector2(ax - 2.0, band_top + 1.8),
                        Vector2(ax, band_top - 0.5),
                        Vector2(ax + 2.0, band_top + 1.8),
                        Vector2(ax + 4.6, band_top + 6.0),
                        Vector2(ax + 4.6, band_bot - 1.5),
                ])
                draw_polyline(ogive, gold, 1.3)
                # vetrata: rosa in vetro elementale PULSANTE
                var rc: Vector2 = Vector2(ax, band_c + 2.5)
                var glass: Color = Color(el.r, el.g, el.b, 0.55 + 0.45 * pulse)
                draw_circle(rc, 3.6, glass)
                draw_circle(rc + Vector2(-1.3, -1.3), 1.6,
                                Color(glow.r, glow.g, glow.b, 0.65 + 0.35 * pulse))
                # piombi della vetrata
                draw_line(rc + Vector2(-3.4, 0.0), rc + Vector2(3.4, 0.0),
                                violet.darkened(0.15), 0.8)
                draw_line(rc + Vector2(0.0, -3.4), rc + Vector2(0.0, 3.4),
                                violet.darkened(0.15), 0.8)
                # rilievo aureo del rosone + scintilla
                draw_arc(rc, 4.0, 0.0, TAU, 12, gold_dark, 0.8)
                draw_circle(rc + Vector2(-1.8, -1.8), 0.7, Color(1.0, 1.0, 0.95, 0.9))
        # montanti dorati tra gli archi
        for m_i in 2:
                var mx: float = ox - 5.5 + 11.0 * float(m_i)
                draw_rect(Rect2(mx - 0.8, band_top + 2.0, 1.6,
                                band_bot - band_top - 3.5), gold_dark, true)
                draw_rect(Rect2(mx - 0.5, band_top + 2.0, 0.8,
                                band_bot - band_top - 3.5), gold, true)
        # alone elementale attorno al traforo
        draw_circle(Vector2(ox, band_c), PILLAR_W * 0.75,
                        Color(glow.r, glow.g, glow.b, 0.10 + 0.07 * pulse))

        # --- 4) CAPITELLO a crockets + astragalo + abaco ---
        # astragalo (collare aureo alla base del capitello)
        draw_rect(Rect2(ox - core_half - 2.0, astragal_y, core_w + 4.0, 2.6),
                        gold_dark, true)
        draw_rect(Rect2(ox - core_half - 2.0, astragal_y, core_w + 4.0, 1.0),
                        gold, true)
        # campana del capitello (si allarga verso l'alto)
        var bell_hw_bot: float = core_half + 1.0
        var bell_hw_top: float = PILLAR_W * 0.36
        var bell_pts := PackedVector2Array([
                Vector2(ox - bell_hw_bot, bell_bot),
                Vector2(ox - bell_hw_top, bell_top),
                Vector2(ox + bell_hw_top, bell_top),
                Vector2(ox + bell_hw_bot, bell_bot),
        ])
        draw_colored_polygon(bell_pts, sand)
        draw_polyline(bell_pts, sand_dark, 1.0)
        draw_line(Vector2(ox - bell_hw_bot + 1.0, bell_bot),
                        Vector2(ox - bell_hw_top + 1.0, bell_top), sand_light, 1.1)
        # crockets: foglie rigide sui bordi della campana (bronzo + punta oro)
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                for k_i in 3:
                        var kk: float = (float(k_i) + 0.6) / 3.0
                        var by: float = lerpf(bell_bot - 1.0, bell_top + 1.0, kk)
                        var bx: float = sgn * lerpf(bell_hw_bot, bell_hw_top, kk)
                        var leaf := PackedVector2Array([
                                Vector2(ox + bx, by + 2.6),
                                Vector2(ox + bx + sgn * 4.6, by - 0.4),
                                Vector2(ox + bx + sgn * 1.6, by - 3.4),
                                Vector2(ox + bx, by - 1.6),
                        ])
                        draw_colored_polygon(leaf, verd_dark)
                        draw_circle(Vector2(ox + bx + sgn * 3.6, by - 0.6), 0.9, gold)
        # abaco (lastra) con intarsio aureo
        draw_rect(Rect2(ox - PILLAR_W * 0.40, abacus_top,
                        PILLAR_W * 0.80, 6.0), lime, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.40, abacus_top,
                        PILLAR_W * 0.80, 1.4), lime_light, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.40, abacus_top + 4.6,
                        PILLAR_W * 0.80, 1.4), lime_dark, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.40, abacus_top + 2.4,
                        PILLAR_W * 0.80, 1.1), gold, true)

        # --- 5) GUGLIA ottagonale a 3 facce con crockets + pomo aureo ---
        var spire_h: float = spire_base - spire_apex
        var spire_half: float = PILLAR_W * 0.32
        # faccia sinistra (luce)
        draw_colored_polygon(PackedVector2Array([
                Vector2(ox - spire_half, spire_base),
                Vector2(ox - spire_half * 0.18, spire_base),
                Vector2(ox, spire_apex),
                Vector2(ox - spire_half * 0.62, spire_apex),
        ]), lime_light)
        # faccia centrale (media)
        draw_colored_polygon(PackedVector2Array([
                Vector2(ox - spire_half * 0.18, spire_base),
                Vector2(ox + spire_half * 0.30, spire_base),
                Vector2(ox + spire_half * 0.40, spire_apex),
                Vector2(ox, spire_apex),
        ]), lime)
        # faccia destra (ombra)
        draw_colored_polygon(PackedVector2Array([
                Vector2(ox + spire_half * 0.30, spire_base),
                Vector2(ox + spire_half, spire_base),
                Vector2(ox + spire_half * 0.72, spire_apex),
                Vector2(ox + spire_half * 0.40, spire_apex),
        ]), lime_dark)
        # filo d'oro alla base della guglia
        draw_rect(Rect2(ox - spire_half - 1.0, spire_base - 1.6,
                        spire_half * 2.0 + 2.0, 1.6), gold_dark, true)
        # crockets dorati sui due bordi (piccoli rampicanti a uncino)
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                for k_i in 3:
                        var tt: float = 0.72 - 0.22 * float(k_i)
                        var ky: float = spire_base - spire_h * tt
                        var kx: float = sgn * spire_half * tt
                        var hook := PackedVector2Array([
                                Vector2(ox + kx, ky + 2.2),
                                Vector2(ox + kx + sgn * 3.4, ky - 0.2),
                                Vector2(ox + kx, ky - 2.4),
                        ])
                        draw_colored_polygon(hook, gold)
                        draw_polyline(hook, gold_dark, 0.6)
        # pomo aureo + croce fiorita finiale
        draw_circle(Vector2(ox, finial_y), 2.8, gold_dark)
        draw_circle(Vector2(ox - 0.7, finial_y - 0.7), 1.6, gold)
        draw_circle(Vector2(ox - 1.1, finial_y - 1.1), 0.6, gold_light)
        draw_line(Vector2(ox, finial_y - 2.6), Vector2(ox, finial_y - 6.8),
                        gold, 1.2)
        draw_line(Vector2(ox - 1.9, finial_y - 4.2), Vector2(ox + 1.9, finial_y - 4.2),
                        gold, 1.0)
        draw_circle(Vector2(ox, finial_y - 7.4), 0.9, gold_light)

        # --- 6) crepe per i colpi subiti (con bagliore elementale interno) ---
        var damage: int = C.BOSS_ARENA_PILLAR_HP - hp
        for d in damage:
                if d >= _cracks.size():
                        break
                var cr: Dictionary = _cracks[d]
                _draw_crack(ox, shaft_top, shaft_bot, core_w, cr, el, pulse)

        # --- 7) flash bianco del colpo ---
        if _hit_flash_ms > 0.0:
                var fl: float = _hit_flash_ms / SHAKE_MS
                draw_rect(Rect2(ox - PILLAR_W * 0.5, top, PILLAR_W, PILLAR_H),
                                Color(1.0, 1.0, 1.0, 0.28 * fl), true)


func _draw_collapsing() -> void:
        var gp: Dictionary = _gothic_palette()
        var lime: Color = gp.lime
        var lime_light: Color = gp.lime_light
        var lime_dark: Color = gp.lime_dark
        var sand: Color = gp.sand
        var gold: Color = gp.gold
        var el: Color = gp.el
        var top: float = -PILLAR_H * 0.5
        # tremolio crescente + colonna che affonda e si inclina
        var k: float = 1.0 - clampf(_collapse_ms / COLLAPSE_MS, 0.0, 1.0)
        var tremble: float = (1.0 - k) * 3.0 * sin(_t * 63.0)
        var sink: float = k * k * PILLAR_H * 0.42
        var tilt: float = k * deg_to_rad(7.0 + 5.0 * sin(_seed))
        draw_set_transform(Vector2(tremble, sink), tilt, Vector2.ONE)
        # fusto a fascio semplificato che sprofonda
        var core_w: float = 26.0
        var shaft_top: float = top + 37.0
        draw_rect(Rect2(-core_w * 0.5, shaft_top, core_w * 0.38,
                        PILLAR_H - 37.0 - 36.0), lime_light, true)
        draw_rect(Rect2(-core_w * 0.5 + core_w * 0.38, shaft_top, core_w * 0.30,
                        PILLAR_H - 37.0 - 36.0), lime, true)
        draw_rect(Rect2(-core_w * 0.5 + core_w * 0.68, shaft_top, core_w * 0.32,
                        PILLAR_H - 37.0 - 36.0), lime_dark, true)
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                draw_rect(Rect2(sgn * 16.5 - 2.6, shaft_top + 4.0, 5.2,
                                PILLAR_H - 37.0 - 42.0), sand, true)
                draw_rect(Rect2(sgn * 16.5 - 2.6, shaft_top + 1.0, 5.2, 3.0),
                                gold.darkened(0.35), true)
        # bagliore del traforo che si spegne
        var fade: float = 1.0 - k
        draw_rect(Rect2(-core_w * 0.62, 2.0, core_w * 1.24, 14.0),
                        Color(el.r, el.g, el.b, 0.55 * fade), true)
        # guglia che si abbatte (pende sempre piu')
        var spire_half: float = PILLAR_W * 0.32
        draw_colored_polygon(PackedVector2Array([
                Vector2(-spire_half, shaft_top - 2.0),
                Vector2(spire_half, shaft_top - 2.0),
                Vector2(0.0, shaft_top - 20.0 - 8.0 * k),
        ]), lime)
        # blocchi che schizzano via durante il crollo (pietra, arenaria, ori)
        for i in 6:
                var ang: float = PI + TAU * 0.5 * float(i) / 6.0
                var dist: float = k * (30.0 + 22.0 * sin(_seed + float(i) * 1.7))
                var bp: Vector2 = Vector2(cos(ang) * dist - 4.0,
                                sin(ang) * dist * 0.4 - 4.0)
                if i % 3 == 0:
                        draw_rect(Rect2(bp, Vector2(8.0, 8.0)), lime.darkened(0.15), true)
                elif i % 3 == 1:
                        draw_rect(Rect2(bp, Vector2(7.0, 6.0)), sand.darkened(0.1), true)
                else:
                        draw_rect(Rect2(bp, Vector2(4.5, 4.5)), gold, true)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # polvere bassa
        for i in 3:
                var dk: float = clampf(k * 1.4 - float(i) * 0.12, 0.0, 1.0)
                draw_circle(Vector2(-26.0 + float(i) * 26.0, PILLAR_H * 0.5 - 10.0),
                                (12.0 + 26.0 * dk) * (1.0 - 0.3 * float(i)),
                                Color(0.46, 0.42, 0.38, 0.30 * (1.0 - dk * 0.5)))


func _draw_rubble() -> void:
        var gp: Dictionary = _gothic_palette()
        var lime: Color = gp.lime
        var sand: Color = gp.sand
        var sand_dark: Color = gp.sand_dark
        var verd: Color = gp.verdigris
        var gold: Color = gp.gold
        var gold_dark: Color = gp.gold_dark
        var el: Color = gp.el
        var bottom: float = PILLAR_H * 0.5
        # TASK 42 (fix): il cumolo SITTA SUL FILO DI TERRA della base (il
        # vecchio disegno lo centrava a meta' altezza e "volava")
        var ground: float = bottom - 6.0
        var pile_c: float = bottom - 24.0    # baricentro del cumulo
        # ombra larga e bassa a terra
        draw_circle(Vector2(0.0, ground - 2.0), PILLAR_W * 0.80,
                        Color(0.0, 0.0, 0.0, 0.28))
        # cumulo: blocchi irregolari in due pietre + arenaria
        var mound := [
                {"p": Vector2(-14.0, pile_c + 8.0), "s": Vector2(27.0, 12.0),
                        "c": lime.darkened(0.08)},
                {"p": Vector2(11.0, pile_c + 7.0), "s": Vector2(24.0, 10.0),
                        "c": sand_dark},
                {"p": Vector2(-2.0, pile_c - 4.0), "s": Vector2(28.0, 14.0),
                        "c": lime},
                {"p": Vector2(-13.0, pile_c - 9.0), "s": Vector2(16.0, 9.0),
                        "c": sand},
        ]
        for m in mound:
                draw_rect(Rect2(m.p - m.s * 0.5, m.s), m.c, true)
                draw_rect(Rect2(m.p - m.s * 0.5, m.s * 0.30),
                                Color(m.c.r + 0.10, m.c.g + 0.10, m.c.b + 0.10), true)
        # frammento di arco a ogiva sopravvissuto (traforo in oro)
        draw_polyline(PackedVector2Array([
                Vector2(-16.0, pile_c + 4.0), Vector2(-16.0, pile_c - 5.0),
                Vector2(-11.5, pile_c - 9.0), Vector2(-7.0, pile_c - 11.5),
                Vector2(-2.5, pile_c - 9.0),
        ]), gold_dark, 1.6)
        # schegge di vetrata elementale sparse nel cumulo
        for g_i in 4:
                var gx: float = -12.0 + 8.0 * float(g_i) + 3.0 * sin(_seed + float(g_i))
                var gy: float = pile_c - 2.0 + 5.0 * cos(_seed * 2.0 + float(g_i))
                var shard := PackedVector2Array([
                        Vector2(gx, gy - 2.6), Vector2(gx + 2.0, gy),
                        Vector2(gx, gy + 2.6), Vector2(gx - 2.0, gy),
                ])
                draw_colored_polygon(shard, Color(el.r, el.g, el.b, 0.8))
                draw_circle(Vector2(gx - 0.7, gy - 0.7), 0.6,
                                Color(1.0, 1.0, 1.0, 0.6))
        # anello bronzeo spezzato + crocket dorato
        draw_arc(Vector2(9.0, pile_c + 2.0), 6.0, PI * 0.15, PI * 0.85, 10, verd, 2.2)
        draw_colored_polygon(PackedVector2Array([
                Vector2(-6.0, pile_c - 12.0), Vector2(-1.0, pile_c - 10.0),
                Vector2(-4.0, pile_c - 15.0),
        ]), gold)
        # sassolini
        for i in 5:
                var ang: float = _seed + float(i) * 1.9
                var rr: float = 24.0 + 12.0 * absf(sin(_seed * 2.0 + float(i)))
                draw_circle(Vector2(cos(ang) * rr,
                                ground - 3.0 + sin(ang) * rr * 0.18),
                                2.6, lime.darkened(0.25))
        # braci elementali morenti nel cumulo
        var ember: float = 0.35 + 0.30 * sin(_t * 2.0 + _seed)
        for i in 3:
                draw_circle(Vector2(-8.0 + float(i) * 8.0, pile_c + 4.0
                                + 3.0 * sin(_seed + float(i))),
                                1.8, Color(el.r, el.g, el.b, ember * (0.7 - 0.15 * float(i))))
        # ultimo riflesso del pomo aureo sepolto
        draw_circle(Vector2(14.0, pile_c - 8.0), 1.4,
                        Color(gold.r, gold.g, gold.b, 0.5 + 0.3 * sin(_t * 1.7 + _seed)))
        draw_circle(Vector2(13.5, pile_c - 8.5), 0.6,
                        Color(gp.gold_light.r, gp.gold_light.g, gp.gold_light.b, 0.8))


# Blocco smussato: faccia poligonale con angoli tagliati + bordo superiore
# illuminato + bordo inferiore in ombra.
func _chamfer_block(center: Vector2, w: float, h: float, cut: float,
                base: Color, light: Color, dark: Color) -> void:
        var x0: float = center.x - w * 0.5
        var y0: float = center.y - h * 0.5
        var pts := PackedVector2Array([
                Vector2(x0 + cut, y0),
                Vector2(x0 + w - cut, y0),
                Vector2(x0 + w, y0 + cut),
                Vector2(x0 + w, y0 + h - cut),
                Vector2(x0 + w - cut, y0 + h),
                Vector2(x0 + cut, y0 + h),
                Vector2(x0, y0 + h - cut),
                Vector2(x0, y0 + cut),
        ])
        draw_colored_polygon(pts, base)
        draw_polyline(PackedVector2Array([
                pts[0], pts[1], pts[2],
        ]), light, 1.4)
        draw_polyline(PackedVector2Array([
                pts[5], pts[6], pts[7],
        ]), light, 1.0)
        draw_polyline(PackedVector2Array([
                pts[3], pts[4], pts[5],
        ]), dark, 1.4)
        draw_line(Vector2(x0, y0 + cut), Vector2(x0, y0 + h - cut), dark, 1.0)


# Crepa a zigzag verticale con diramazione, deterministica; il condotto
# elementale TRASPARE dalla frattura (bagliore interno pulsante).
func _draw_crack(ox: float, shaft_top: float, shaft_bottom: float,
                shaft_w: float, cr: Dictionary, el: Color, pulse: float) -> void:
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
                if yy > shaft_bottom:
                        yy = shaft_bottom - (yy - shaft_bottom)
                pts.append(Vector2(ox + wob, yy))
        if pts.size() >= 2:
                draw_polyline(pts, dark, 2.4)
                # bagliore elementale dentro la crepa (il condotto e' esposto)
                draw_polyline(pts, Color(el.r, el.g, el.b, 0.45 + 0.35 * pulse), 1.0)
                # diramazione a meta'
                var mid_i: int = pts.size() / 2
                var branch: Vector2 = pts[mid_i] + Vector2(side * 7.0, 6.0)
                draw_line(pts[mid_i], branch, dark, 1.6)
                draw_line(pts[mid_i] + Vector2(side * 1.0, 1.0),
                                branch - Vector2(side * 1.5, 1.5),
                                Color(el.r, el.g, el.b, 0.30 + 0.25 * pulse), 0.8)
        # scheggia mancante sul bordo (con orlo illuminato)
        draw_circle(Vector2(ox + side * shaft_w * 0.5, y0), 3.0,
                        Color(0.05, 0.05, 0.06, 0.55))
        draw_circle(Vector2(ox + side * shaft_w * 0.5 - side * 2.4, y0 - 1.0),
                        1.1, Color(0.9, 0.88, 0.82, 0.5))

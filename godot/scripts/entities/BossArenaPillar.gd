## BossArenaPillar.gd — TASK 39 (L'Arena del Boss) / TASK 42 restyle gotico
## polycromo / TASK 43 restile GOTICO CATTEDRALE ispirato a Bloodborne.
##
## PINNACOLO-CATTEDRALE ELEMENTALE: 4 architetture a tema dell'elemento
## DEBOLE del boss, disposte nell'arena. Meccanica (INVARIATA dal Task 39):
##   * il player (proiettili e fendenti reliquia) li frantuma in 3 colpi:
##     a ogni colpo compaiono crepe LUMINESCENTI (il condotto elementale
##     traspare dalle fratture) + schegge mancanti + flash + scintille
##   * i PROIETTILI DEL BOSS vengono BLOCCATI (consumati) e infliggono 1
##     danno al pilastro: la copertura si consuma durante lo scontro
##   * al crollo: scricchiolio, polvere, la corona di pinnacoli si abbatte e
##     spawna 5 frammenti (ArenaDebris) lanciati a raggiera che danneggiano
##     il boss
##   * sul fondo resta un cumulo di macerie gotiche (feedback permanente)
##   * TASK 43: un pilastro crollato NON RISORGE MAI — ne' col rinnovo
##     periodico dell'arena, ne' alla morte del player (lo snapshot di
##     sessione riapplica le macerie al continue)
##
## GRAFICA (TASK 43 — gotico VITTORIANO alla Yharnam/Bloodborne, zero asset
## esterni): silhouette verticale OPRESSIVA (68x184, era 54x130) in pietra
## fredda sporcata dalla luce calda di una candela:
##   * INFERRIATA in ferro battuto attorno al plinto (punte di lancia)
##   * PLINTO a TRE gradini smussati con scotia viola, TORO bronzeo
##     ossidato fibbiato in oro e GRINFIE a foglia-artiglio agli angoli
##   * FUSTO A FASCIO: nucleo calcareo freddo a 3 facce con VENE DI MARMO
##     deterministiche, corsi di arenaria calda, STRIE DI EROSIONE, muschio
##     e 2 colonnine addossate con anelli aurei
##   * DUE FINESTRE LANCEOLATE a vetrate elementali pulsanti con montante
##     dorato (le "luci" del condotto)
##   * BANDA A TRAFORO: 3 archi a ogiva in oro con rosoni in VETRO COLORATO
##     elementale e montanti dorati
##   * ROSONE MAGGIORE: finestra circolare a 8 RAGGI con petali in vetro
##     elementale alternato, doppio anello aureo, perni e alone pulsante
##   * DOCCIONE (gargoyle) appollaiato sull'abaco: demone bronzeo ripiegato
##     con ali chiuse, corna e OCCHI che bruciano dell'elemento
##   * CAPITELLO a crockets (foglie rigide in bronzo con punte dorate),
##     astragalo aureo e abaco intarsiato
##   * CORONA DI 3 PINNACOLI: guglia centrale + 2 gugliole laterali con
##     crockets a uncino, pomo aureo e croce fiorita finiale
##   * LANTERNA A TURIBOLO appesa all'angolo dell'abaco: fiamma di CANDELA
##     ambra che guizza e ondeggia (contrasto caldo/freddo di Yharnam)
##   * crepe a zigzag con BAGLIORE elementale interno, micro-shake al
##     colpo, tremolio e polvere al crollo
extends Node2D

const C = preload("res://scripts/core/GameConstants.gd")
const DebrisClass = preload("res://scripts/entities/ArenaDebris.gd")

enum PillarState { STANDING, COLLAPSING, RUBBLE }

const SHAKE_MS: float = 140.0
const COLLAPSE_MS: float = 430.0
const PILLAR_W: float = 68.0
const PILLAR_H: float = 184.0

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


## TASK 43: ripristino da SNAPSHOT DI SESSIONE (continue nella boss room
## dopo la morte del player). Le architetture distrutte NON risorgono:
## `rubble` = era gia' crollato -> resta un cumulo di macerie per sempre
## (niente animazione ne' frammenti: il crollo era gia' avvenuto prima
## della morte). Altrimenti il pilastro in piedi recupera gli HP salvati
## (le crepe deterministiche derivano dagli HP e riappaiono da sole).
func restore_from_snapshot(rubble: bool,
                new_hp: int = C.BOSS_ARENA_PILLAR_HP) -> void:
        if rubble:
                hp = 0
                state = PillarState.RUBBLE
                _collapse_ms = 0.0
                _fragments_spawned = true
                _hit_flash_ms = 0.0
        else:
                hp = clampi(new_hp, 1, C.BOSS_ARENA_PILLAR_HP)
                if state != PillarState.STANDING:
                        state = PillarState.STANDING
                _collapse_ms = 0.0
                _hit_flash_ms = 0.0
        queue_redraw()


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
                        frag.setup(position + vel.normalized() * 24.0, vel, tint,
                                        0.85 + 0.45 * absf(cos(_seed + float(i))))
        # polvere del crollo (cumulo piu' largo: architettura piu' grande)
        if EffectsManager:
                for i in 3:
                        var puff: Node2D = EffectsManager.spawn_explosion(
                                        position + Vector2(randf_range(-18.0, 18.0),
                                                        randf_range(0.0, 24.0)),
                                        Color(0.42, 0.38, 0.34), 12, 0.9)
                        _debris_parent.add_child(puff)


# ============================================================================
# Palette gotica polycroma (derivata dall'elemento per il vetro/il bagliore).
# TASK 43: aggiunte le famiglie FERRO BATTUTO, ARDESIA in ombra profonda e
# AMBRA di candela (contrasto caldo/freddo alla Bloodborne): 9 famiglie.
# ============================================================================

func _gothic_palette() -> Dictionary:
        var el: Color = _pal.get("color", Color.WHITE)
        var glow: Color = _pal.get("glow", Color.WHITE)
        # arenaria calda con un velo dell'elemento (legge il tema a colpo d'occhio)
        var sand: Color = Color(0.66, 0.57, 0.43).lerp(el, 0.10)
        return {
                "lime": Color(0.50, 0.52, 0.58),          # calcarea fredda
                "lime_light": Color(0.66, 0.68, 0.74),
                "lime_dark": Color(0.32, 0.34, 0.41),
                "slate": Color(0.24, 0.26, 0.32),          # ardesia in ombra
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
                "iron": Color(0.17, 0.16, 0.19),            # ferro battuto
                "iron_light": Color(0.30, 0.29, 0.33),
                "candle": Color(1.00, 0.74, 0.36),          # fiamma della lanterna
                "candle_glow": Color(1.00, 0.60, 0.22),
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


# ============================================================================
# STATO: IN PIEDI — pinnacolo-cattedrale (dal basso verso l'alto)
# ============================================================================

func _draw_standing() -> void:
        var gp: Dictionary = _gothic_palette()
        # micro-shake mentre lampeggia il colpo subito
        var ox: float = 0.0
        if _hit_flash_ms > 0.0:
                ox = sin(_t * 90.0) * 2.2 * (_hit_flash_ms / SHAKE_MS)
        var top: float = -PILLAR_H * 0.5              # -92
        var bottom: float = PILLAR_H * 0.5            # 92

        # geometria verticale (dal basso verso l'alto)
        var plinth1_y: float = bottom - 14.0          # 78..92  gradino maior
        var plinth2_y: float = bottom - 23.0          # 69..78  gradino medio
        var scotia_y: float = bottom - 26.0           # 66..69  (in ombra)
        var torus_y: float = bottom - 31.0            # 61..66  anello bronzo
        var shaft_bot: float = bottom - 31.0          # 61
        var shaft_top: float = top + 54.0             # -38
        var band_bot: float = 24.0                    # banda a traforo
        var band_top: float = 0.0
        var rose_cy: float = -17.0                    # centro rosone
        var bell_bot: float = shaft_top - 1.0         # -39
        var bell_top: float = top + 41.0              # -51
        var abacus_top: float = top + 35.0            # -57
        var core_w: float = 32.0
        var pulse: float = 0.55 + 0.45 * sin(_t * 2.6 + _seed)

        # --- 0) ombra a terra ---
        draw_circle(Vector2(0.0, bottom - 4.0), PILLAR_W * 0.66,
                        Color(0.0, 0.0, 0.0, 0.32))

        # --- 1) INFERRIATA in ferro battuto attorno al plinto ---
        _draw_fence(bottom, gp)

        # --- 2) PLINTO a tre gradini + scotia + toro bronzeo + grinfie ---
        _chamfer_block(Vector2(ox, (plinth1_y + bottom) * 0.5),
                        PILLAR_W, 14.0, 5.0, gp.lime, gp.lime_light, gp.lime_dark)
        _chamfer_block(Vector2(ox, (plinth2_y + plinth1_y) * 0.5),
                        PILLAR_W * 0.84, 9.0, 4.0, gp.lime, gp.lime_light,
                        gp.lime_dark)
        draw_rect(Rect2(ox - PILLAR_W * 0.36, plinth2_y - 3.0,
                        PILLAR_W * 0.72, 4.0), gp.slate, true)
        # scotia: profilo concavo in penombra viola
        draw_rect(Rect2(ox - PILLAR_W * 0.36, scotia_y,
                        PILLAR_W * 0.72, 3.0), gp.violet, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.36, scotia_y,
                        PILLAR_W * 0.72, 1.2), gp.lime_dark, true)
        # toro bronzeo ossidato con fibbie dorate
        draw_rect(Rect2(ox - PILLAR_W * 0.39, torus_y,
                        PILLAR_W * 0.78, 5.0), gp.verdigris, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.39, torus_y,
                        PILLAR_W * 0.78, 1.2), gp.verdigris.lightened(0.25), true)
        draw_rect(Rect2(ox - PILLAR_W * 0.39, torus_y + 3.8,
                        PILLAR_W * 0.78, 1.2), gp.verdigris_dark, true)
        for s_i in 4:
                var stud_x: float = ox - PILLAR_W * 0.27 \
                                + PILLAR_W * 0.18 * float(s_i)
                draw_rect(Rect2(stud_x - 1.1, torus_y - 0.6, 2.2, 6.2),
                                gp.gold_dark, true)
                draw_rect(Rect2(stud_x - 0.7, torus_y - 0.2, 1.4, 3.0),
                                gp.gold, true)
        # grinfie: foglie-artiglio agli angoli del gradino medio
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                var claw := PackedVector2Array([
                        Vector2(ox + sgn * PILLAR_W * 0.41, plinth2_y - 1.0),
                        Vector2(ox + sgn * (PILLAR_W * 0.41 + 7.0), plinth2_y + 4.0),
                        Vector2(ox + sgn * (PILLAR_W * 0.41 + 3.4), plinth2_y + 8.0),
                        Vector2(ox + sgn * PILLAR_W * 0.39, plinth2_y + 6.5),
                ])
                draw_colored_polygon(claw, gp.verdigris_dark)
                draw_polyline(claw, gp.gold_dark, 0.9)

        # --- 3) FUSTO A FASCIO: facce, corsi, vene, erosione, colonnine ---
        _draw_shaft(ox, shaft_top, shaft_bot, core_w, band_top, band_bot,
                        rose_cy, gp)

        # --- 4) FINESTRE LANCEOLATE a vetrata elementale (luci del condotto) ---
        _draw_lancet(ox - 8.5, 53.0, 22.0, 10.0, gp, pulse)
        _draw_lancet(ox + 8.5, 53.0, 22.0, 10.0, gp, pulse)
        # alone elementale basso attorno alle lancette
        draw_circle(Vector2(ox, 42.0), PILLAR_W * 0.52,
                        Color(gp.glow.r, gp.glow.g, gp.glow.b,
                                        0.08 + 0.06 * pulse))

        # --- 5) BANDA A TRAFORO: 3 archi a ogiva con rosoni in vetro ---
        _draw_tracery_band(ox, band_top, band_bot, gp, pulse)

        # --- 6) ROSONE MAGGIORE a 8 raggi + arcate cieche soprastanti ---
        _draw_rose_window(ox, rose_cy, gp)
        for a_i in 2:
                var ax: float = ox - 7.0 + 14.0 * float(a_i)
                draw_arc(Vector2(ax, shaft_top - 2.0), 4.2, PI, TAU, 8,
                                gp.gold_dark, 1.0)
        draw_rect(Rect2(ox - 15.0, shaft_top - 2.6, 30.0, 1.4), gp.gold, true)

        # --- 7) CAPITELLO a crockets + astragalo + abaco ---
        _draw_capital(ox, shaft_top, bell_bot, bell_top, abacus_top, gp)

        # --- 8) CORONA DI 3 PINNACOLI con croce fiorita finiale ---
        _draw_pinnacle_crown(ox, abacus_top, gp)

        # --- 9) DOCCIONE (gargoyle) appollaiato sull'abaco ---
        var garg_side: float = -1.0 if fmod(_seed, 2.0) < 1.0 else 1.0
        _draw_gargoyle(ox, abacus_top, garg_side, gp)

        # --- 10) LANTERNA A TURIBOLO appesa all'angolo opposto ---
        _draw_lantern(ox, abacus_top, -garg_side, gp)

        # --- 11) crepe per i colpi subiti (bagliore elementale) ---
        var damage: int = C.BOSS_ARENA_PILLAR_HP - hp
        for d in damage:
                if d >= _cracks.size():
                        break
                var cr: Dictionary = _cracks[d]
                _draw_crack(ox, shaft_top, shaft_bot, core_w, cr, gp.el, pulse)

        # --- 12) flash bianco del colpo ---
        if _hit_flash_ms > 0.0:
                var fl: float = _hit_flash_ms / SHAKE_MS
                draw_rect(Rect2(ox - PILLAR_W * 0.5, top, PILLAR_W, PILLAR_H),
                                Color(1.0, 1.0, 1.0, 0.28 * fl), true)


# --- Inferriata in ferro battuto: anello di 12 picche attorno al plinto.
# Le picche DIETRO spuntano sopra i gradini (profondita'), quelle davanti
# incorniciano la base; due montanti orizzontali in ferro scuro.
func _draw_fence(bottom: float, gp: Dictionary) -> void:
        var iron: Color = gp.iron
        var iron_light: Color = gp.iron_light
        # TASK 43 (fix visibilita'): raggio MAGGIORE della semilarghezza del
        # plinto (34), altrimenti i gradini la nascondono tutta — l'anello
        # deve CINGERE la base come le inferriate di Yharnam.
        var ring_r: float = PILLAR_W * 0.62          # ~42
        var base_y: float = bottom - 4.0
        for i in 12:
                var ang: float = TAU * float(i) / 12.0 + 0.13
                var bx: float = cos(ang) * ring_r
                var by: float = base_y + sin(ang) * 3.0
                var hgt: float = 22.0 + 3.0 * absf(cos(_seed + float(i)))
                # picca: asta + punta di lancia triangolare
                draw_rect(Rect2(bx - 1.0, by - hgt, 2.0, hgt), iron, true)
                draw_rect(Rect2(bx - 1.0, by - hgt, 0.8, hgt), iron_light, true)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(bx - 2.0, by - hgt + 2.2),
                        Vector2(bx, by - hgt - 3.8),
                        Vector2(bx + 2.0, by - hgt + 2.2),
                ]), iron_light)
                draw_circle(Vector2(bx, by - hgt - 3.8), 0.9, gp.gold_dark)
        # due montanti orizzontali (il piu' alto sporge sopra i gradini)
        draw_rect(Rect2(-ring_r, base_y - 24.0, ring_r * 2.0, 1.8), iron, true)
        draw_rect(Rect2(-ring_r, base_y - 13.0, ring_r * 2.0, 2.0), iron, true)


# --- Fusto a fascio: nucleo calcareo a 3 facce con corsi, vene di marmo,
# strie di erosione, muschio e 2 colonnine addossate ad anelli aurei.
func _draw_shaft(ox: float, shaft_top: float, shaft_bot: float,
                core_w: float, band_top: float, band_bot: float,
                rose_cy: float, gp: Dictionary) -> void:
        var lime: Color = gp.lime
        var lime_light: Color = gp.lime_light
        var lime_dark: Color = gp.lime_dark
        var slate: Color = gp.slate
        var sand: Color = gp.sand
        var sand_light: Color = gp.sand_light
        var sand_dark: Color = gp.sand_dark
        var marble: Color = gp.marble
        var core_half: float = core_w * 0.5
        var shaft_h: float = shaft_bot - shaft_top
        # faccia sinistra (luce), centrale (media), destra (ombra)
        draw_rect(Rect2(ox - core_half, shaft_top, core_w * 0.38, shaft_h),
                        lime_light, true)
        draw_rect(Rect2(ox - core_half + core_w * 0.38, shaft_top,
                        core_w * 0.30, shaft_h), lime, true)
        draw_rect(Rect2(ox - core_half + core_w * 0.68, shaft_top,
                        core_w * 0.32, shaft_h), lime_dark, true)
        # giunti dei blocchi (corsi sottili in ombra, 6 corsi)
        for j_i in 6:
                var jy: float = shaft_top + shaft_h * (0.10 + 0.145 * float(j_i))
                if jy > band_top - 2.0 and jy < band_bot + 2.0:
                        continue  # non attraversare il pannello a traforo
                draw_rect(Rect2(ox - core_half, jy, core_w, 1.1),
                                slate, true)
        # corsi di arenaria calda (polycromia, 3 fasce)
        for s_i in 3:
                var sy: float = [55.0, 27.5, shaft_top + 3.5][s_i]
                var sh: float = [3.6, 3.2, 3.6][s_i]
                draw_rect(Rect2(ox - core_half, sy, core_w, sh), sand, true)
                draw_rect(Rect2(ox - core_half, sy, core_w, 1.0), sand_light, true)
                draw_rect(Rect2(ox - core_half, sy + sh - 1.0, core_w, 1.0),
                                sand_dark, true)
        # vene di marmo deterministiche (evitano traforo e rosone)
        for v_i in 4:
                var vpts := PackedVector2Array()
                var v_side: float = -1.0 if v_i % 2 == 0 else 1.0
                var lane_top: float = 30.0 if v_i < 2 else -35.0
                for i in 6:
                        var vx: float = ox + v_side * (3.0 + 7.0 * absf(sin(
                                        _seed * 1.7 + float(i) * 1.3 + float(v_i) * 2.4)))
                        var vy: float = lane_top + float(i) * 4.6 \
                                        + 2.6 * sin(_seed + float(i))
                        if vy > band_top - 1.0 and vy < band_bot + 1.0:
                                continue
                        if absf(vy - rose_cy) < 15.5:
                                continue
                        vpts.append(Vector2(vx, vy))
                if vpts.size() >= 2:
                        draw_polyline(vpts, marble, 1.0)
        # strie di EROSIONE verticale (decadenza di Yharnam)
        for e_i in 3:
                var ex: float = ox - 9.0 + 9.0 * float(e_i) \
                                + 2.0 * sin(_seed * 2.2 + float(e_i))
                draw_rect(Rect2(ex, shaft_top + 6.0, 2.0,
                                shaft_h - 20.0 - 6.0 * float(e_i)),
                                Color(slate.r, slate.g, slate.b, 0.22), true)
        # colonnine addossate con anelli dorati
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                var colx: float = ox + sgn * 19.0
                draw_rect(Rect2(colx - 2.6, shaft_top + 4.0, 5.2,
                                shaft_h - 8.0), sand.lightened(0.06), true)
                draw_rect(Rect2(colx - 2.6, shaft_top + 4.0, 1.6,
                                shaft_h - 8.0), sand_light, true)
                draw_rect(Rect2(colx + 1.0, shaft_top + 4.0, 1.6,
                                shaft_h - 8.0), sand_dark, true)
                # basi, capitelli e anello centrale (anelli aurei)
                draw_rect(Rect2(colx - 3.3, shaft_bot - 5.0, 6.6, 3.0),
                                gp.gold_dark, true)
                draw_rect(Rect2(colx - 3.3, shaft_top + 1.0, 6.6, 3.0),
                                gp.gold_dark, true)
                draw_rect(Rect2(colx - 2.9, (shaft_top + shaft_bot) * 0.5 - 3.6,
                                5.8, 2.4), gp.gold, true)
                draw_rect(Rect2(colx - 2.9, shaft_bot - 4.4, 5.8, 1.2),
                                gp.gold, true)
                draw_rect(Rect2(colx - 2.9, shaft_top + 1.6, 5.8, 1.2),
                                gp.gold, true)
        # muschio sul lato in ombra (deterministico)
        for m_i in 8:
                var hx: float = sin(_seed * 3.3 + float(m_i) * 2.19)
                var hy: float = cos(_seed * 2.1 + float(m_i) * 1.37)
                draw_circle(Vector2(ox - 11.0 + 5.0 * hx, 51.0 + 6.5 * hy),
                                1.4, Color(gp.moss.r, gp.moss.g, gp.moss.b, 0.8))


# --- Finestra lanceolata: ogiva aurea con vetro elementale pulsante,
# montante a piombo e davanzale in arenaria.
func _draw_lancet(cx: float, y_bot: float, h: float, w: float,
                gp: Dictionary, pulse: float) -> void:
        var gold: Color = gp.gold
        var gold_dark: Color = gp.gold_dark
        var lead: Color = gp.violet.darkened(0.15)
        var el: Color = gp.el
        var glow: Color = gp.glow
        var y_top: float = y_bot - h
        var hw: float = w * 0.5
        var apex: Vector2 = Vector2(cx, y_top - 3.5)
        # vetro elementale (poligono a punta)
        var glass := PackedVector2Array([
                Vector2(cx - hw + 1.2, y_bot - 1.5),
                Vector2(cx - hw + 1.2, y_top + 3.5),
                apex + Vector2(0.0, 1.8),
                Vector2(cx + hw - 1.2, y_top + 3.5),
                Vector2(cx + hw - 1.2, y_bot - 1.5),
        ])
        draw_colored_polygon(glass, Color(el.r, el.g, el.b, 0.40 + 0.38 * pulse))
        # montante centrale + traversa a piombo
        draw_line(Vector2(cx, y_top + 2.5), Vector2(cx, y_bot - 1.5), lead, 1.1)
        draw_line(Vector2(cx - hw + 1.4, y_bot - 7.0),
                        Vector2(cx + hw - 1.4, y_bot - 7.0), lead, 0.9)
        # scintilla del vetro
        draw_circle(Vector2(cx - 1.0, y_bot - h * 0.55), 1.1,
                        Color(glow.r, glow.g, glow.b, 0.55 + 0.35 * pulse))
        # cornice aurea a ogiva + piedritti
        draw_line(Vector2(cx - hw, y_top + 3.5), Vector2(cx - hw, y_bot),
                        gold, 1.2)
        draw_line(Vector2(cx + hw, y_top + 3.5), Vector2(cx + hw, y_bot),
                        gold, 1.2)
        draw_line(Vector2(cx - hw, y_top + 3.5), apex, gold, 1.2)
        draw_line(Vector2(cx + hw, y_top + 3.5), apex, gold, 1.2)
        draw_circle(apex, 1.1, gold_dark)
        # davanzale in arenaria
        draw_rect(Rect2(cx - hw - 2.5, y_bot, w + 5.0, 3.2), gp.sand, true)
        draw_rect(Rect2(cx - hw - 2.5, y_bot, w + 5.0, 1.0), gp.sand_light, true)


# --- Banda a traforo: 3 archetti a ogiva in oro con rosoni in vetro
# elementale PULSANTE e montanti dorati (il "cuore" del condotto).
func _draw_tracery_band(ox: float, band_top: float, band_bot: float,
                gp: Dictionary, pulse: float) -> void:
        var gold: Color = gp.gold
        var gold_dark: Color = gp.gold_dark
        var lead: Color = gp.violet.darkened(0.15)
        var el: Color = gp.el
        var glow: Color = gp.glow
        var band_w: float = PILLAR_W * 0.82
        draw_rect(Rect2(ox - band_w * 0.5, band_top, band_w,
                        band_bot - band_top), gp.violet, true)
        draw_rect(Rect2(ox - band_w * 0.5, band_top, band_w, 1.6),
                        gp.violet.darkened(0.3), true)
        draw_rect(Rect2(ox - band_w * 0.5, band_bot - 1.6, band_w, 1.6),
                        gp.violet.darkened(0.3), true)
        var band_c: float = (band_top + band_bot) * 0.5
        for a_i in 3:
                var ax: float = ox - 15.0 + 15.0 * float(a_i)
                # archetto a ogiva in oro
                var ogive := PackedVector2Array([
                        Vector2(ax - 5.6, band_bot - 1.5),
                        Vector2(ax - 5.6, band_top + 6.0),
                        Vector2(ax - 2.4, band_top + 1.8),
                        Vector2(ax, band_top - 0.5),
                        Vector2(ax + 2.4, band_top + 1.8),
                        Vector2(ax + 5.6, band_top + 6.0),
                        Vector2(ax + 5.6, band_bot - 1.5),
                ])
                draw_polyline(ogive, gold, 1.3)
                # vetrata: rosa in vetro elementale PULSANTE
                var rc: Vector2 = Vector2(ax, band_c + 2.5)
                var glass: Color = Color(el.r, el.g, el.b, 0.55 + 0.45 * pulse)
                draw_circle(rc, 4.2, glass)
                draw_circle(rc + Vector2(-1.5, -1.5), 1.8,
                                Color(glow.r, glow.g, glow.b, 0.65 + 0.35 * pulse))
                # piombi della vetrata
                draw_line(rc + Vector2(-4.0, 0.0), rc + Vector2(4.0, 0.0), lead, 0.8)
                draw_line(rc + Vector2(0.0, -4.0), rc + Vector2(0.0, 4.0), lead, 0.8)
                # rilievo aureo del rosone + scintilla
                draw_arc(rc, 4.6, 0.0, TAU, 12, gold_dark, 0.8)
                draw_circle(rc + Vector2(-2.0, -2.0), 0.8, Color(1.0, 1.0, 0.95, 0.9))
        # montanti dorati tra gli archi
        for m_i in 2:
                var mx: float = ox - 7.5 + 15.0 * float(m_i)
                draw_rect(Rect2(mx - 0.8, band_top + 2.0, 1.6,
                                band_bot - band_top - 3.5), gold_dark, true)
                draw_rect(Rect2(mx - 0.5, band_top + 2.0, 0.8,
                                band_bot - band_top - 3.5), gold, true)
        # alone elementale attorno al traforo
        draw_circle(Vector2(ox, band_c), PILLAR_W * 0.78,
                        Color(glow.r, glow.g, glow.b, 0.10 + 0.07 * pulse))

# --- Rosone maggiore: finestra circolare a 8 raggi con petali in vetro
# elementale alternato (chiaro/scuro), doppio anello aureo, perni dorati
# e alone pulsante — la "faccia" della cattedrale in miniatura.
func _draw_rose_window(ox: float, cy: float, gp: Dictionary) -> void:
        var el: Color = gp.el
        var glow: Color = gp.glow
        var gold: Color = gp.gold
        var gold_dark: Color = gp.gold_dark
        var lime_light: Color = gp.lime_light
        var rp: float = 0.60 + 0.40 * sin(_t * 2.2 + _seed * 1.3)
        var c: Vector2 = Vector2(ox, cy)
        # alone esterno pulsante
        draw_circle(c, 17.0, Color(glow.r, glow.g, glow.b, 0.09 + 0.07 * rp))
        # anello esterno in pietra + doppio filetto aureo
        draw_arc(c, 13.0, 0.0, TAU, 20, lime_light, 3.2)
        draw_arc(c, 11.2, 0.0, TAU, 20, gold, 1.4)
        draw_arc(c, 10.2, 0.0, TAU, 20, gold_dark, 0.8)
        # petali in vetro tra i raggi (alternati chiaro/scuro)
        for i in 8:
                var a0: float = TAU * float(i) / 8.0 + 0.39
                var a1: float = TAU * float(i + 1) / 8.0 + 0.39
                var p0: Vector2 = c + Vector2(cos(a0), sin(a0)) * 4.2
                var p1: Vector2 = c + Vector2(cos(a1), sin(a1)) * 4.2
                var pr1: Vector2 = c + Vector2(cos(a0), sin(a0)) * 9.6
                var pr2: Vector2 = c + Vector2(cos(a1), sin(a1)) * 9.6
                var petal := PackedVector2Array([p0, pr1, pr2, p1])
                var petal_col: Color = el if i % 2 == 0 else el.darkened(0.35)
                draw_colored_polygon(petal, Color(petal_col.r, petal_col.g,
                                petal_col.b, 0.45 + 0.35 * rp))
        # raggi (traforo in oro scuro)
        for i in 8:
                var ang: float = TAU * float(i) / 8.0 + 0.39
                draw_line(c + Vector2(cos(ang), sin(ang)) * 3.2,
                                c + Vector2(cos(ang), sin(ang)) * 9.8, gold_dark, 1.2)
        # ombrello centrale + perno aureo + scintilla
        draw_circle(c, 3.4, Color(el.r, el.g, el.b, 0.55 + 0.35 * rp))
        draw_circle(c, 2.2, gold)
        draw_circle(c + Vector2(-0.9, -0.9), 0.8, Color(1.0, 1.0, 0.95, 0.9))
        # perni dorati sull'anello (ai 4 punti cardinali)
        for i in 4:
                var ang: float = TAU * float(i) / 4.0 + 0.39
                draw_circle(c + Vector2(cos(ang), sin(ang)) * 12.0, 1.1, gold)


# --- Doccione (gargoyle): demone bronzeo appollaiato sull'abaco, ali
# ripiegate sul dorso, corna ricurve e OCCHI che bruciano dell'elemento.
# La sentinella silenziosa della cattedrale (ispirazione Bloodborne).
func _draw_gargoyle(ox: float, abacus_top: float, sgn: float,
                gp: Dictionary) -> void:
        var verd: Color = gp.verdigris
        var verd_dark: Color = gp.verdigris_dark
        var gold_dark: Color = gp.gold_dark
        var el: Color = gp.el
        var eye: float = 0.5 + 0.5 * sin(_t * 3.1 + _seed * 2.0)
        var x0: float = ox + sgn * 23.0
        var by: float = abacus_top
        # ala ripiegata sul dorso (dietro il corpo)
        var wing := PackedVector2Array([
                Vector2(x0 - sgn * 2.0, by - 4.0),
                Vector2(x0 - sgn * 9.0, by - 11.0),
                Vector2(x0 - sgn * 11.0, by - 4.0),
                Vector2(x0 - sgn * 6.0, by - 1.0),
        ])
        draw_colored_polygon(wing, verd_dark)
        # costole dell'ala
        draw_line(wing[0], Vector2(x0 - sgn * 8.0, by - 8.5), verd, 0.8)
        draw_line(wing[0] + Vector2(0.0, -2.0),
                        Vector2(x0 - sgn * 10.0, by - 6.0), verd, 0.8)
        # coda che si avvolge sull'abaco
        draw_polyline(PackedVector2Array([
                Vector2(x0 + sgn * 2.0, by - 2.0),
                Vector2(x0 - sgn * 3.0, by - 0.5),
                Vector2(x0 - sgn * 7.0, by - 2.5),
                Vector2(x0 - sgn * 8.5, by - 0.8),
        ]), verd_dark, 1.2)
        # corpo accovacciato (gobba)
        var body := PackedVector2Array([
                Vector2(x0 - sgn * 5.0, by),
                Vector2(x0 - sgn * 4.0, by - 6.0),
                Vector2(x0 - sgn * 1.0, by - 10.0),
                Vector2(x0 + sgn * 3.0, by - 9.0),
                Vector2(x0 + sgn * 5.0, by - 4.0),
                Vector2(x0 + sgn * 4.0, by),
        ])
        draw_colored_polygon(body, verd)
        draw_polyline(body, verd_dark, 0.8)
        # testa cornuta protesa in fuori
        draw_colored_polygon(PackedVector2Array([
                Vector2(x0 + sgn * 2.0, by - 10.0),
                Vector2(x0 + sgn * 6.5, by - 12.5),
                Vector2(x0 + sgn * 8.0, by - 9.5),
                Vector2(x0 + sgn * 5.0, by - 7.0),
        ]), verd_dark)
        # corna ricurve
        draw_line(Vector2(x0 + sgn * 3.5, by - 11.5),
                        Vector2(x0 + sgn * 3.0, by - 15.0), gold_dark, 1.0)
        draw_line(Vector2(x0 + sgn * 5.5, by - 12.0),
                        Vector2(x0 + sgn * 6.5, by - 15.5), gold_dark, 1.0)
        # occhi che bruciano dell'elemento
        draw_circle(Vector2(x0 + sgn * 4.0, by - 10.5), 0.9,
                        Color(el.r, el.g, el.b, 0.55 + 0.45 * eye))
        draw_circle(Vector2(x0 + sgn * 6.6, by - 10.0), 0.8,
                        Color(el.r, el.g, el.b, 0.45 + 0.45 * eye))
        # zampe anteriori artigliate sull'orlo dell'abaco
        draw_line(Vector2(x0 + sgn * 4.0, by - 7.0),
                        Vector2(x0 + sgn * 5.0, by - 1.0), verd_dark, 1.2)
        draw_line(Vector2(x0 + sgn * 5.0, by - 1.0),
                        Vector2(x0 + sgn * 6.6, by + 0.6), verd, 0.8)
        draw_line(Vector2(x0 + sgn * 5.0, by - 1.0),
                        Vector2(x0 + sgn * 3.6, by + 0.6), verd, 0.8)


# --- Capitello a crockets: astragalo aureo, campana in arenaria con
# foglie rigide in bronzo e punte dorate, abaco intarsiato.
func _draw_capital(ox: float, shaft_top: float, bell_bot: float,
                bell_top: float, abacus_top: float, gp: Dictionary) -> void:
        # astragalo (collare aureo alla base del capitello)
        draw_rect(Rect2(ox - 18.0, shaft_top - 3.0, 36.0, 2.6),
                        gp.gold_dark, true)
        draw_rect(Rect2(ox - 18.0, shaft_top - 3.0, 36.0, 1.0), gp.gold, true)
        # campana (si allarga verso l'alto)
        var bell_hw_bot: float = 17.0
        var bell_hw_top: float = PILLAR_W * 0.35
        var bell_pts := PackedVector2Array([
                Vector2(ox - bell_hw_bot, bell_bot),
                Vector2(ox - bell_hw_top, bell_top),
                Vector2(ox + bell_hw_top, bell_top),
                Vector2(ox + bell_hw_bot, bell_bot),
        ])
        draw_colored_polygon(bell_pts, gp.sand)
        draw_polyline(bell_pts, gp.sand_dark, 1.0)
        draw_line(Vector2(ox - bell_hw_bot + 1.0, bell_bot),
                        Vector2(ox - bell_hw_top + 1.0, bell_top), gp.sand_light, 1.1)
        # crockets: foglie rigide sui bordi della campana (4 per lato)
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                for k_i in 4:
                        var kk: float = (float(k_i) + 0.6) / 4.0
                        var by: float = lerpf(bell_bot - 1.0, bell_top + 1.0, kk)
                        var bx: float = sgn * lerpf(bell_hw_bot, bell_hw_top, kk)
                        var leaf := PackedVector2Array([
                                Vector2(ox + bx, by + 2.6),
                                Vector2(ox + bx + sgn * 4.8, by - 0.4),
                                Vector2(ox + bx + sgn * 1.7, by - 3.6),
                                Vector2(ox + bx, by - 1.6),
                        ])
                        draw_colored_polygon(leaf, gp.verdigris_dark)
                        draw_circle(Vector2(ox + bx + sgn * 3.8, by - 0.6),
                                        0.9, gp.gold)
        # abaco (lastra) con intarsio aureo
        draw_rect(Rect2(ox - PILLAR_W * 0.44, abacus_top,
                        PILLAR_W * 0.88, 6.0), gp.lime, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.44, abacus_top,
                        PILLAR_W * 0.88, 1.4), gp.lime_light, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.44, abacus_top + 4.6,
                        PILLAR_W * 0.88, 1.4), gp.lime_dark, true)
        draw_rect(Rect2(ox - PILLAR_W * 0.44, abacus_top + 2.4,
                        PILLAR_W * 0.88, 1.1), gp.gold, true)


# --- Corona di 3 pinnacoli: guglia centrale maggiore + 2 gugliole.
func _draw_pinnacle_crown(ox: float, base_y: float, gp: Dictionary) -> void:
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                _draw_spire(ox + sgn * 14.0, base_y, 15.0, 5.5, gp, false)
        _draw_spire(ox, base_y, 31.0, 11.0, gp, true)


# Guglia a 3 facce con crockets a uncino; quella principale porta pomo
# aureo e croce fiorita finiale.
func _draw_spire(cx: float, base_y: float, h: float, half_w: float,
                gp: Dictionary, main: bool) -> void:
        var apex: float = base_y - h
        # faccia sinistra (luce)
        draw_colored_polygon(PackedVector2Array([
                Vector2(cx - half_w, base_y),
                Vector2(cx - half_w * 0.18, base_y),
                Vector2(cx, apex),
                Vector2(cx - half_w * 0.62, apex),
        ]), gp.lime_light)
        # faccia centrale (media)
        draw_colored_polygon(PackedVector2Array([
                Vector2(cx - half_w * 0.18, base_y),
                Vector2(cx + half_w * 0.30, base_y),
                Vector2(cx + half_w * 0.40, apex),
                Vector2(cx, apex),
        ]), gp.lime)
        # faccia destra (ombra)
        draw_colored_polygon(PackedVector2Array([
                Vector2(cx + half_w * 0.30, base_y),
                Vector2(cx + half_w, base_y),
                Vector2(cx + half_w * 0.72, apex),
                Vector2(cx + half_w * 0.40, apex),
        ]), gp.lime_dark)
        # filo d'oro alla base della guglia
        draw_rect(Rect2(cx - half_w - 1.0, base_y - 1.6,
                        half_w * 2.0 + 2.0, 1.6), gp.gold_dark, true)
        # crockets dorati sui due bordi (piccoli rampicanti a uncino)
        var n_ck: int = 3 if main else 2
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                for k_i in n_ck:
                        var tt: float = 0.72 - 0.22 * float(k_i)
                        var ky: float = base_y - h * tt
                        var kx: float = sgn * half_w * tt
                        var hook := PackedVector2Array([
                                Vector2(cx + kx, ky + 2.2),
                                Vector2(cx + kx + sgn * 3.4, ky - 0.2),
                                Vector2(cx + kx, ky - 2.4),
                        ])
                        draw_colored_polygon(hook, gp.gold)
                        draw_polyline(hook, gp.gold_dark, 0.6)
        if main:
                # pomo aureo + croce fiorita finiale
                draw_circle(Vector2(cx, apex - 3.0), 2.8, gp.gold_dark)
                draw_circle(Vector2(cx - 0.7, apex - 3.7), 1.6, gp.gold)
                draw_circle(Vector2(cx - 1.1, apex - 4.1), 0.6, gp.gold_light)
                draw_line(Vector2(cx, apex - 5.6), Vector2(cx, apex - 10.0),
                                gp.gold, 1.2)
                draw_line(Vector2(cx - 1.9, apex - 7.2),
                                Vector2(cx + 1.9, apex - 7.2), gp.gold, 1.0)
                draw_circle(Vector2(cx, apex - 10.6), 0.9, gp.gold_light)
        else:
                draw_circle(Vector2(cx, apex - 1.8), 1.4, gp.gold)
                draw_circle(Vector2(cx - 0.5, apex - 2.3), 0.6, gp.gold_light)


# --- Lanterna a turibolo appesa all'angolo dell'abaco (lato opposto al
# doccione): catena in ferro, corpo in ferro battuto e FIAMMA DI CANDELA
# ambra che guizza e ondeggia — la luce calda che sporca la pietra fredda.
func _draw_lantern(ox: float, abacus_top: float, sgn: float,
                gp: Dictionary) -> void:
        var iron: Color = gp.iron
        var iron_light: Color = gp.iron_light
        var candle: Color = gp.candle
        var candle_glow: Color = gp.candle_glow
        var flick: float = 0.55 + 0.45 * absf(sin(_t * 7.3 + _seed * 1.7)) \
                        * absf(sin(_t * 2.9 + _seed))
        # dondolio lento della lanterna appesa
        var sway: float = sin(_t * 1.1 + _seed) * 1.6
        var ax: float = ox + sgn * 26.0
        var ay: float = abacus_top + 2.0
        var lx: float = ox + sgn * 28.0 + sway
        var ly: float = abacus_top + 15.0
        # catena a 2 tratti + maglia centrale
        var mid: Vector2 = Vector2(lerpf(ax, lx, 0.5), lerpf(ay, ly - 7.0, 0.5))
        draw_line(Vector2(ax, ay), mid, iron, 1.4)
        draw_line(mid, Vector2(lx, ly - 7.0), iron, 1.4)
        draw_circle(mid, 1.2, iron_light)
        # alone caldo che guizza
        draw_circle(Vector2(lx, ly), 11.0,
                        Color(candle_glow.r, candle_glow.g, candle_glow.b,
                                        0.12 + 0.09 * flick))
        # cappello piramidale in ferro
        draw_colored_polygon(PackedVector2Array([
                Vector2(lx - 5.0, ly - 4.6),
                Vector2(lx + 5.0, ly - 4.6),
                Vector2(lx + 3.0, ly - 8.2),
                Vector2(lx - 3.0, ly - 8.2),
        ]), iron)
        # corpo: ferri + vetro ambra + fiamma
        draw_rect(Rect2(lx - 4.0, ly - 4.6, 8.0, 10.5), iron, true)
        draw_rect(Rect2(lx - 3.1, ly - 3.7, 6.2, 8.7),
                        Color(candle.r, candle.g, candle.b,
                                        0.38 + 0.45 * flick), true)
        draw_circle(Vector2(lx, ly + 0.8), 2.0,
                        Color(candle_glow.r, candle_glow.g, candle_glow.b,
                                        0.78 + 0.22 * flick))
        draw_circle(Vector2(lx - 0.5, ly - 0.2), 0.9, Color(1.0, 0.95, 0.8, 0.9))
        # base + gancio
        draw_rect(Rect2(lx - 2.6, ly + 5.9, 5.2, 1.8), iron, true)
        draw_rect(Rect2(lx - 0.7, ly + 7.7, 1.4, 2.2), iron, true)


# ============================================================================
# STATO: CROLLINO IN CORSO — la colonna sprofonda, la corona di pinnacoli
# si abbatte, blocchi polycromi schizzano via e i vetri si spengono.
# ============================================================================

func _draw_collapsing() -> void:
        var gp: Dictionary = _gothic_palette()
        var lime: Color = gp.lime
        var lime_light: Color = gp.lime_light
        var lime_dark: Color = gp.lime_dark
        var sand: Color = gp.sand
        var slate: Color = gp.slate
        var gold: Color = gp.gold
        var el: Color = gp.el
        var top: float = -PILLAR_H * 0.5
        var bottom: float = PILLAR_H * 0.5
        # tremolio crescente + colonna che affonda e si inclina
        var k: float = 1.0 - clampf(_collapse_ms / COLLAPSE_MS, 0.0, 1.0)
        var tremble: float = (1.0 - k) * 3.0 * sin(_t * 63.0)
        var sink: float = k * k * PILLAR_H * 0.46
        var tilt: float = k * deg_to_rad(7.0 + 5.0 * sin(_seed))
        draw_set_transform(Vector2(tremble, sink), tilt, Vector2.ONE)
        # fusto a fascio semplificato che sprofonda (3 facce + colonnine)
        var core_w: float = 32.0
        var shaft_top: float = top + 54.0
        var shaft_h: float = bottom - 31.0 - shaft_top
        draw_rect(Rect2(-core_w * 0.5, shaft_top, core_w * 0.38, shaft_h),
                        lime_light, true)
        draw_rect(Rect2(-core_w * 0.5 + core_w * 0.38, shaft_top,
                        core_w * 0.30, shaft_h), lime, true)
        draw_rect(Rect2(-core_w * 0.5 + core_w * 0.68, shaft_top,
                        core_w * 0.32, shaft_h), lime_dark, true)
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                draw_rect(Rect2(sgn * 19.0 - 2.6, shaft_top + 4.0, 5.2,
                                shaft_h - 8.0), sand, true)
                draw_rect(Rect2(sgn * 19.0 - 2.6, shaft_top + 1.0, 5.2, 3.0),
                                gold.darkened(0.35), true)
        # bagliore di traforo e rosone che si spengono
        var fade: float = 1.0 - k
        draw_rect(Rect2(-core_w * 0.7, 1.0, core_w * 1.4, 24.0),
                        Color(el.r, el.g, el.b, 0.50 * fade), true)
        draw_circle(Vector2(0.0, -17.0), 12.0,
                        Color(el.r, el.g, el.b, 0.45 * fade))
        # capitello + corona di pinnacoli che si abbatte (pende sempre piu')
        draw_rect(Rect2(-17.0, shaft_top - 14.0, 34.0, 13.0), sand, true)
        var spire_half: float = PILLAR_W * 0.16
        draw_colored_polygon(PackedVector2Array([
                Vector2(-spire_half - 8.0, shaft_top - 14.0),
                Vector2(-spire_half + 8.0, shaft_top - 14.0),
                Vector2(-6.0 - 6.0 * k, shaft_top - 38.0 - 10.0 * k),
        ]), lime)
        draw_colored_polygon(PackedVector2Array([
                Vector2(spire_half - 8.0, shaft_top - 14.0),
                Vector2(spire_half + 8.0, shaft_top - 14.0),
                Vector2(6.0 + 6.0 * k, shaft_top - 38.0 - 10.0 * k),
        ]), lime_dark)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        # blocchi che schizzano via durante il crollo
        # (5 famiglie: calcarea / arenaria / oro / ardesia / vetro elementale)
        for i in 8:
                var ang: float = PI + TAU * 0.5 * float(i) / 8.0
                var dist: float = k * (34.0 + 26.0 * sin(_seed + float(i) * 1.7))
                var bp: Vector2 = Vector2(cos(ang) * dist - 4.0,
                                sin(ang) * dist * 0.4 - 4.0)
                match i % 5:
                        0:
                                draw_rect(Rect2(bp, Vector2(9.0, 8.0)),
                                                lime.darkened(0.15), true)
                        1:
                                draw_rect(Rect2(bp, Vector2(7.5, 6.5)),
                                                sand.darkened(0.1), true)
                        2:
                                draw_rect(Rect2(bp, Vector2(4.5, 4.5)), gold, true)
                        3:
                                draw_rect(Rect2(bp, Vector2(6.0, 5.0)), slate, true)
                        _:
                                draw_rect(Rect2(bp, Vector2(4.0, 4.0)),
                                                Color(el.r, el.g, el.b, 0.85), true)
        # polvere bassa (piu' larga: architettura piu' grande)
        for i in 3:
                var dk: float = clampf(k * 1.4 - float(i) * 0.12, 0.0, 1.0)
                draw_circle(Vector2(-32.0 + float(i) * 32.0, bottom - 10.0),
                                (14.0 + 32.0 * dk) * (1.0 - 0.3 * float(i)),
                                Color(0.46, 0.42, 0.38, 0.30 * (1.0 - dk * 0.5)))

# ============================================================================
# STATO: MACERIE — cumulo permanente sul filo di terra. TASK 43: piu'
# grande e piu' ricco: rottami di rosone, testa del doccione, picche
# dell'inferriata, lanterna spenta, maglie di catena, vetri, ori e braci.
# ============================================================================

func _draw_rubble() -> void:
        var gp: Dictionary = _gothic_palette()
        var lime: Color = gp.lime
        var sand: Color = gp.sand
        var sand_dark: Color = gp.sand_dark
        var slate: Color = gp.slate
        var verd: Color = gp.verdigris
        var verd_dark: Color = gp.verdigris_dark
        var gold: Color = gp.gold
        var gold_dark: Color = gp.gold_dark
        var iron: Color = gp.iron
        var el: Color = gp.el
        var bottom: float = PILLAR_H * 0.5
        # il cumulo SITTA SUL FILO DI TERRA della base
        var ground: float = bottom - 6.0
        var pile_c: float = bottom - 26.0   # baricentro del cumulo
        # ombra larga e bassa a terra
        draw_circle(Vector2(0.0, ground - 2.0), PILLAR_W * 0.86,
                        Color(0.0, 0.0, 0.0, 0.28))
        # cumulo: blocchi irregolari in tre pietre (piu' largo del T42)
        var mound := [
                {"p": Vector2(-17.0, pile_c + 9.0), "s": Vector2(30.0, 13.0),
                        "c": lime.darkened(0.08)},
                {"p": Vector2(14.0, pile_c + 8.0), "s": Vector2(26.0, 11.0),
                        "c": sand_dark},
                {"p": Vector2(-2.0, pile_c - 4.0), "s": Vector2(32.0, 15.0),
                        "c": lime},
                {"p": Vector2(-16.0, pile_c - 10.0), "s": Vector2(17.0, 9.0),
                        "c": sand},
                {"p": Vector2(13.0, pile_c - 11.0), "s": Vector2(15.0, 8.0),
                        "c": slate.lightened(0.05)},
        ]
        for m in mound:
                draw_rect(Rect2(m.p - m.s * 0.5, m.s), m.c, true)
                draw_rect(Rect2(m.p - m.s * 0.5, m.s * 0.30),
                                Color(m.c.r + 0.10, m.c.g + 0.10, m.c.b + 0.10), true)
        # frammento di arco a ogiva sopravvissuto (traforo in oro)
        draw_polyline(PackedVector2Array([
                Vector2(-20.0, pile_c + 4.0), Vector2(-20.0, pile_c - 5.0),
                Vector2(-15.5, pile_c - 9.0), Vector2(-11.0, pile_c - 12.0),
                Vector2(-6.5, pile_c - 10.0),
        ]), gold_dark, 1.6)
        # ROSONE SPEZZATO: mezzo anello con monconi di raggi
        draw_arc(Vector2(9.0, pile_c - 6.0), 7.0, PI * 0.05, PI * 0.95, 12,
                        lime.lightened(0.12), 2.2)
        draw_arc(Vector2(9.0, pile_c - 6.0), 5.6, PI * 0.1, PI * 0.9, 10,
                        gold, 1.2)
        draw_line(Vector2(4.5, pile_c - 6.0), Vector2(9.0, pile_c - 12.5),
                        gold_dark, 1.0)
        draw_line(Vector2(12.0, pile_c - 5.5), Vector2(14.5, pile_c - 11.0),
                        gold_dark, 1.0)
        # TESTA DEL DOCCIONE sepolta nel cumulo: corna + occhi quasi spenti
        draw_colored_polygon(PackedVector2Array([
                Vector2(-13.5, pile_c - 14.0), Vector2(-8.0, pile_c - 12.5),
                Vector2(-8.5, pile_c - 7.5), Vector2(-13.0, pile_c - 8.0),
        ]), verd_dark)
        draw_line(Vector2(-13.0, pile_c - 13.5),
                        Vector2(-14.5, pile_c - 17.0), gold_dark, 1.0)
        draw_line(Vector2(-8.8, pile_c - 12.2),
                        Vector2(-7.5, pile_c - 15.8), gold_dark, 1.0)
        var dead_eye: float = 0.22 + 0.18 * sin(_t * 1.6 + _seed)
        draw_circle(Vector2(-11.8, pile_c - 11.0), 0.8,
                        Color(el.r, el.g, el.b, dead_eye))
        draw_circle(Vector2(-9.6, pile_c - 10.6), 0.7,
                        Color(el.r, el.g, el.b, dead_eye * 0.8))
        # PICCHE DELL'INFERRIATA conficcate oblique nel cumulo
        for s_i in 2:
                var sgn: float = -1.0 if s_i == 0 else 1.0
                var spx: float = sgn * 22.0
                draw_line(Vector2(spx - sgn * 3.0, ground - 2.0),
                                Vector2(spx + sgn * 2.0, pile_c - 13.0
                                                - 3.0 * float(s_i)), iron, 1.8)
                draw_colored_polygon(PackedVector2Array([
                        Vector2(spx + sgn * 1.2, pile_c - 11.5 - 3.0 * float(s_i)),
                        Vector2(spx + sgn * 3.2, pile_c - 14.5 - 3.0 * float(s_i)),
                        Vector2(spx + sgn * 2.6, pile_c - 10.5 - 3.0 * float(s_i)),
                ]), iron)
        # LANTERNA SPENTA: ferri storti, vetro annerito, ultimo guizzo
        draw_rect(Rect2(19.0, pile_c - 5.0, 6.0, 8.0), iron, true)
        draw_rect(Rect2(19.8, pile_c - 4.2, 4.4, 6.4),
                        Color(0.30, 0.24, 0.18, 0.9), true)
        draw_circle(Vector2(22.0, pile_c - 1.0), 0.8,
                        Color(gp.candle_glow.r, gp.candle_glow.g,
                                        gp.candle_glow.b, 0.14 + 0.10 * sin(_t * 2.4)))
        # maglie di catena sparse
        draw_arc(Vector2(-2.0, pile_c - 16.0), 1.8, 0.0, TAU, 8, iron, 0.9)
        draw_arc(Vector2(1.5, pile_c - 14.5), 1.5, 0.0, TAU, 8, iron, 0.8)
        # schegge di vetrata elementale sparse nel cumulo
        for g_i in 5:
                var gx: float = -14.0 + 7.0 * float(g_i) + 3.0 * sin(_seed + float(g_i))
                var gy: float = pile_c - 2.0 + 5.0 * cos(_seed * 2.0 + float(g_i))
                var shard := PackedVector2Array([
                        Vector2(gx, gy - 2.6), Vector2(gx + 2.0, gy),
                        Vector2(gx, gy + 2.6), Vector2(gx - 2.0, gy),
                ])
                draw_colored_polygon(shard, Color(el.r, el.g, el.b, 0.8))
                draw_circle(Vector2(gx - 0.7, gy - 0.7), 0.6,
                                Color(1.0, 1.0, 1.0, 0.6))
        # anello bronzeo spezzato + crocket dorato
        draw_arc(Vector2(11.0, pile_c + 2.0), 6.5, PI * 0.15, PI * 0.85, 10,
                        verd, 2.2)
        draw_colored_polygon(PackedVector2Array([
                Vector2(-6.0, pile_c - 15.0), Vector2(-1.0, pile_c - 13.0),
                Vector2(-4.0, pile_c - 18.0),
        ]), gold)
        # sassolini sparsi (piu' larghi)
        for i in 6:
                var ang: float = _seed + float(i) * 1.9
                var rr: float = 27.0 + 13.0 * absf(sin(_seed * 2.0 + float(i)))
                draw_circle(Vector2(cos(ang) * rr,
                                ground - 3.0 + sin(ang) * rr * 0.18),
                                2.6, lime.darkened(0.25))
        # braci elementali morenti nel cumulo
        var ember: float = 0.35 + 0.30 * sin(_t * 2.0 + _seed)
        for i in 4:
                draw_circle(Vector2(-10.0 + float(i) * 7.0, pile_c + 4.0
                                + 3.0 * sin(_seed + float(i))),
                                1.8, Color(el.r, el.g, el.b,
                                                ember * (0.7 - 0.15 * float(i))))
        # ultimo riflesso del pomo aureo sepolto
        draw_circle(Vector2(15.0, pile_c - 10.0), 1.4,
                        Color(gold.r, gold.g, gold.b,
                                        0.5 + 0.3 * sin(_t * 1.7 + _seed)))
        draw_circle(Vector2(14.5, pile_c - 10.5), 0.6,
                        Color(gp.gold_light.r, gp.gold_light.g,
                                        gp.gold_light.b, 0.8))


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




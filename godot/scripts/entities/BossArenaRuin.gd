## BossArenaRuin.gd — TASK 50: MURO-LABIRINTO IN ROVINA per la stanza del boss.
##
## Sostituisce i pilastri del TASK 39 (l'utente li trovava "troppi e piccoli"):
## l'arena ora e' un LABIRINTO SPEZZATO — segmenti di muraglia antica
## (materiale roccioso poroso da cripta, generati con PixelLab) disposti
## proceduralmente in modo DIVERSO ad ogni partita e ad ogni boss.
##
## Gameplay:
##   * FANNO DA MURO: bloccano i proiettili del boss (copertura fisica) e
##     quelli del player, e bloccano il MOVIMENTO del player (ci si muove
##     TRA i frammenti, come in un rudere). Il boss invece li calpesta:
##     e' una creatura gigante sopra muri bassi — niente repulsione (i
##     pilastri alti del TASK 39 spingevano il boss, qui sarebbe solo fonte
##     di incastri).
##   * SI ROMPONO con i colpi (3 HP): crepe crescenti, poi CROLLO con
##     schegge di pietra (ArenaDebris, ora calcare grigio — TASK 50) e
##     polvere; resta un tappeto di macerie non bloccante, per sempre.
##   * SNAPSHOT/RESTORE (continue): il layout e' deterministico dal seed
##     (run + boss), quindi il restore rigenera lo stesso labirinto e
##     riapplica gli stati (in piedi / macerie + HP residui).
##
## Grafica: crop delal striscia PixelLab 400x100 (h) / 100x400 (v) — una
## cella = 100px sorgente disegnati a 64px (scala 0.64). L'offset di crop
## varia per segmento: dallo stesso nastro escono pezzi DIVERSI.
extends Node2D

enum RuinState { STANDING, RUBBLE }

const C = preload("res://scripts/core/GameConstants.gd")
const DebrisClass = preload("res://scripts/entities/ArenaDebris.gd")

## px sorgente per cella nelle strisce PixelLab (400x100 / 100x400).
const SRC_CELL: float = 100.0
const SRC_CELLS: int = 4
const DRAW_SCALE: float = 64.0 / SRC_CELL

var ruin_index: int = 0
var axis: String = "h"                 # "h" | "v"
var length_cells: int = 3
var hp: int = 3
var state: int = RuinState.STANDING
var origin: Vector2 = Vector2.ZERO     # centro del segmento
var _rng_seed: float = 0.0
var _sprite: Sprite2D
var _rubble_sprites: Array = []
var _cracks: Array = []                # polilinee crack deterministiche
var _collapse_fx_done: bool = false
var _debris_parent: Node = null


static func load_strip_texture(is_vertical: bool) -> Texture2D:
        var path: String = "res://assets/sprites/ruins/ruin_wall_%s.png" \
                        % ("v" if is_vertical else "h")
        var tex: Texture2D = load(path)
        if tex != null:
                return tex
        return load("res://assets/sprites/ruins/ruin_wall_h.png")


func setup(center: Vector2, wall_axis: String, cells: int, seed_val: float,
                idx: int, debris_parent: Node = null) -> void:
        origin = center
        axis = wall_axis
        length_cells = clampi(cells, 1, SRC_CELLS)
        hp = C.BOSS_ARENA_RUIN_HP
        state = RuinState.STANDING
        _rng_seed = seed_val
        ruin_index = idx
        _debris_parent = debris_parent
        position = origin
        z_index = 6  # sopra pavimenti/barili, sotto proiettili e HUD
        _build_wall_sprite()
        _build_cracks()


func _ready() -> void:
        add_to_group("arena_ruins")


# ---------------------------------------------------------------------------
# Geometria / query
# ---------------------------------------------------------------------------

## AABB del muro (solo se in piedi). `pad` gonfia il rettangolo (raggio
## proiettile/player).
func get_rect(pad: float = 0.0) -> Rect2:
        var half: Vector2
        if axis == "h":
                half = Vector2(length_cells * C.TILE_SIZE * 0.5, C.TILE_SIZE * 0.42)
        else:
                half = Vector2(C.TILE_SIZE * 0.42, length_cells * C.TILE_SIZE * 0.5)
        return Rect2(origin - half - Vector2(pad, pad), half * 2.0 + Vector2(pad * 2.0, pad * 2.0))


func is_standing() -> bool:
        return state == RuinState.STANDING


func blocks_point(p: Vector2, pad: float = 0.0) -> bool:
        if not is_standing():
                return false
        return get_rect(pad).has_point(p)


# ---------------------------------------------------------------------------
# Danno / crollo
# ---------------------------------------------------------------------------

## Un colpo (boss o player): -1 HP. Ritorna true se QUESTO colpo l'ha abbattuto.
func take_hit() -> bool:
        if not is_standing():
                return false
        hp -= 1
        if hp <= 0:
                _collapse()
                return true
        _refresh_cracks()
        return false


func _collapse() -> void:
        state = RuinState.RUBBLE
        if _sprite != null and is_instance_valid(_sprite):
                _sprite.queue_free()
                _sprite = null
        _spawn_rubble()
        if not _collapse_fx_done:
                _collapse_fx_done = true
                _spawn_debris()


## Schegge di pietra che volano + polvere del crollo (solo la prima volta:
## il restore dallo snapshot non ripete l'animazione).
## TASK 91 (fix scatti alla distruzione): i 5 frammenti e i 2 sbuffi di
## polvere vengono aggiunti con call_deferred (mai ~10 nodi + GPU nel
## frame del colpo fatale) e gli sbuffi sono 2 invece di 3.
func _spawn_debris() -> void:
        var parent: Node = _debris_parent if _debris_parent != null else get_parent()
        var n: int = C.BOSS_ARENA_RUIN_FRAGMENTS
        for i in n:
                var t: float = float(i) / float(n)
                var pos_along: Vector2 = (Vector2(1, 0) if axis == "h" else Vector2(0, 1)) \
                                * (t - 0.5) * length_cells * C.TILE_SIZE
                var ang: float = TAU * t + _rng_seed * 0.7
                var spd: float = 3.6 + 2.2 * absf(sin(_rng_seed + float(i) * 2.3))
                var vel: Vector2 = Vector2(cos(ang), sin(ang) * 0.8 - 0.35) * spd
                var frag: Node2D = DebrisClass.new()
                if frag.has_method("setup"):
                        frag.setup(origin + pos_along + vel.normalized() * 18.0, vel,
                                        Color.WHITE, 0.9 + 0.5 * absf(cos(_rng_seed + float(i))))
                parent.add_child.call_deferred(frag)
        var em: Node = _find_autoload("EffectsManager")
        if em != null:
                for i in 2:
                        var puff: Node2D = em.spawn_blast_smoke(
                                        origin + Vector2(randf_range(-20.0, 20.0),
                                                        randf_range(-8.0, 8.0)),
                                        Color(0.45, 0.40, 0.34), 7)
                        if puff != null:
                                parent.add_child.call_deferred(puff)


## Trova un autoload per nome (EffectsManager, EnvironmentArt, ...).
func _find_autoload(autoload_name: String) -> Node:
        var tree: SceneTree = Engine.get_main_loop() as SceneTree
        if tree == null or tree.root == null:
                return null
        for n in tree.root.get_children():
                if n.name == autoload_name:
                        return n
        return null


## Tappeto di macerie non bloccante lungo l'ingombro del vecchio muro.
func _spawn_rubble() -> void:
        var tex: Texture2D = null
        var env_art: Node = _find_autoload("EnvironmentArt")
        if env_art != null and env_art.has_method("get_rubble_texture"):
                tex = env_art.get_rubble_texture()
        var along: Vector2 = Vector2(1, 0) if axis == "h" else Vector2(0, 1)
        var pieces: int = maxi(2, length_cells)
        for i in pieces:
                var t: float = (float(i) + 0.5) / float(pieces)
                var rs := Sprite2D.new()
                if tex != null:
                        rs.texture = tex
                rs.position = along * (t - 0.5) * length_cells * C.TILE_SIZE \
                                + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
                var rs_scale: float = 0.42 * (0.85 + 0.3 * absf(sin(_rng_seed * 9.1 + float(i))))
                rs.scale = Vector2(rs_scale, rs_scale)
                rs.rotation = _rng_seed * 6.28 + float(i) * 1.3
                rs.self_modulate = Color(0.62, 0.60, 0.58, 0.95)
                rs.z_index = 4
                add_child(rs)
                _rubble_sprites.append(rs)


# ---------------------------------------------------------------------------
# Crepe (overlay procedurale deterministico sugli HP)
# ---------------------------------------------------------------------------

func _build_cracks() -> void:
        _cracks.clear()
        var rng := RandomNumberGenerator.new()
        rng.seed = int(absf(_rng_seed * 7919.0)) & 0x7fffffff
        var half_long: float = (length_cells * C.TILE_SIZE) * 0.5 - 10.0
        var along_x: bool = axis == "h"
        var n: int = C.BOSS_ARENA_RUIN_HP - 1  # crepe progressive per colpo
        for c in n:
                # la crepa cammina lungo l'asse LUNGO del muro con zigzag
                # su entrambi gli assi (le crepe dei muri reali serpeggiano)
                var line: PackedVector2Array = PackedVector2Array()
                var a: float = rng.randf_range(-half_long * 0.6, half_long * 0.6)
                var b: float = rng.randf_range(-9.0, 9.0)
                for s in 6:
                        if along_x:
                                line.append(Vector2(a, b))
                        else:
                                line.append(Vector2(b, a))
                        a += rng.randf_range(-18.0, 18.0)
                        b += rng.randf_range(-16.0, 16.0)
                _cracks.append(line)


func _refresh_cracks() -> void:
        # le crepe si mostrano in base agli HP persi: ridisegna l'overlay
        queue_redraw()


func _draw() -> void:
        if not is_standing() or _cracks.is_empty():
                return
        var lost: int = C.BOSS_ARENA_RUIN_HP - hp
        var dark: Color = Color(0.05, 0.04, 0.04, 0.85)
        for i in mini(lost, _cracks.size()):
                var line: PackedVector2Array = _cracks[i]
                if line.size() < 2:
                        continue
                for s in line.size() - 1:
                        draw_line(line[s], line[s + 1], dark, 2.0)
                # scheggia staccata alla fine della crepa
                draw_circle(line[line.size() - 1], 2.2, dark)


# ---------------------------------------------------------------------------
# Sprite del muro (crop della striscia PixelLab)
# ---------------------------------------------------------------------------

func _build_wall_sprite() -> void:
        var is_v: bool = axis == "v"
        var strip: Texture2D = load_strip_texture(is_v)
        _sprite = Sprite2D.new()
        if strip != null:
                var atlas := AtlasTexture.new()
                atlas.atlas = strip
                # offset di crop casuale (varieta' dallo stesso nastro)
                var max_off_cells: int = SRC_CELLS - length_cells
                var off_cells: int = 0
                if max_off_cells > 0:
                        off_cells = int(clampf(
                                        absf(fposmod(_rng_seed * 3.7, 1.0))
                                        * float(max_off_cells + 1), 0.0,
                                        float(max_off_cells)))
                var region: Rect2
                if is_v:
                        region = Rect2(0.0, off_cells * SRC_CELL, SRC_CELL,
                                        length_cells * SRC_CELL)
                else:
                        region = Rect2(off_cells * SRC_CELL, 0.0,
                                        length_cells * SRC_CELL, SRC_CELL)
                atlas.region = region
                _sprite.texture = atlas
                _sprite.scale = Vector2(DRAW_SCALE, DRAW_SCALE)
        _sprite.z_index = 6
        add_child(_sprite)


# ---------------------------------------------------------------------------
# Snapshot (continue 1P/2P)
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
        return {
                "idx": ruin_index,
                "state": int(state),
                "hp": int(hp),
        }


## Ripristino post-continue: `as_rubble` = era gia' crollato (nessuna
## animazione, solo macerie); altrimenti HP residui + crepe coerenti.
func restore_from_snapshot(as_rubble: bool, hp_left: int = C.BOSS_ARENA_RUIN_HP) -> void:
        if as_rubble:
                hp = 0
                _collapse_fx_done = true  # niente debris: il crollo era avvenuto
                _collapse()
        else:
                hp = clampi(hp_left, 1, C.BOSS_ARENA_RUIN_HP)
                state = RuinState.STANDING
                _refresh_cracks()

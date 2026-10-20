## MazeHazards.gd - TASK 30: hazard ambientali del labirinto.
## =============================================================
## Quattro pericoli generati a ogni livello maze (dal livello 4, in
## quantita' crescente ogni 3 livelli, max 5 per tipo):
##
##   * SABBIE MOBILI (quicksand): cella che rallenta il player del 50%
##     (i nemici passano indenni). Si superano con un salto. Gli stivali
##     della velocita' annullano il malus.
##   * GANASCE (trap): trappola dentata ARMATA visibile a terra. Cattura
##     il player che la calpesta (grounded): -33% energia max (morte se
##     l'energia residua non basta), tenuta 1.5s accorciabile MASHANDO
##     salto/sparo (min 0.6s). Un PROIETTILE del player la fa scattare a
##     vuoto (disarmo, riarmo 4s; dopo una cattura riarmo 5s).
##   * VORAGINE (chasm): appare con telegrafo (crepa + rumble, 1.2s) poi
##     resta APERTA per tutto il livello: chi vi cade dentro perde una
##     vita (salto = passi sopra; ghost = immuni; i nemici camminano sul
##     bordo indenni).
##   * MURO DI ROCCIA (rock wall): cella muro TRA DUE CORRIDOI che si
##     apre/chiude (3s aperto + 0.5s vibrazione + 3s chiuso): scorciatoia
##     per player E nemici (il BFS la attraversa quando aperta). Chi
##     resta imprigionato alla chiusura: player -66% energia max (morte
##     se non basta) e resta bloccato fino alla riapertura; nemico -33%
##     HP max, bloccato finche' chiuso. Nemico UCCISO dal muro = 2x punti
##     (10000) al player vivo piu' vicino.
##
## REGOLE COMUNI (decisioni utente):
##   - I danni ambientali BYPASSANO le armature-reliquia (vanno dritti
##     all'energia): le cariche armatura restano per il combattimento.
##   - Calice (invincibilita'): niente DANNO, ma le ganasce trattengono.
##   - Ghost mode / salto in corso: immuni a tutto (si vola sopra).
##   - GhostReaper e alleati ignorano gli hazard.
##   - RNG dedicato seedato per livello: stesso livello = stessi hazard
##     (determinismo per test e continue).
##   - Rollback: GameConstants.HAZARDS_ENABLED = false.
##
## Il nodo va tra Maze e Player nel tree di MainGame (draw order:
## pavimento -> hazard -> entita'). Le celle dei muri di roccia sono
## registrate in Maze.dynamic_walls cosi' is_wall/BFS/proiettili le
## vedono chiuse/aperte in tempo reale.
extends Node2D
class_name MazeHazards

const C = preload("res://scripts/core/GameConstants.gd")

enum HazardType { QUICKSAND, TRAP, CHASM, ROCK_WALL }

# Stati per tipo:
# QUICKSAND: nessuno stato (sempre attiva).
# TRAP:        ARMED -> SNAPPED (tieni player) -> REARM(timer) -> ARMED
#              ARMED -> SNAPPED_EMPTY (proiettile) -> REARM -> ARMED
# CHASM:       DORMANT(delay casuale) -> CRACK(1.2s) -> OPEN (per sempre)
# ROCK_WALL:   fase ciclica OPEN(3s) -> WARN(0.5s) -> CLOSED(3s) -> OPEN...
enum TrapState { ARMED, SNAPPED, REARM }
enum ChasmState { DORMANT, CRACK, OPEN }
enum WallPhase { OPEN, WARN, CLOSED }

## Referenza al MainGameController (player/player2/spawner/collectible check).
var controller: Node = null

## Lista hazard: Dictionary per elemento.
## Campi comuni: type, cell (Vector2i), sprite (Sprite2D).
## TRAP: state, timer_ms, holding (CharacterBody2D|null), hold_ms.
## CHASM: state, timer_ms, delay_ms.
## ROCK_WALL: phase, phase_ms, axis ("h" passaggio orizzontale / "v"),
##            slab_a/slab_b (Sprite2D), off_a/off_b (offset attuali px).
var hazard_list: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _tex_cache: Dictionary = {}

# Offset (px, centro cella) delle due meta' di roccia per fase: aperto =
# retratte DENTRO i muri adiacenti (la lastra copre la cella vicina, il
# passaggio resta sgombro per ~56 dei 64px); chiuso = compenetrano al centro
# (i denti si incastrano). Il movimento e' inseguimento del target
# (SLAM px/s) cosi' la chiusura "sbatte" e l'apertura scivola. NOTA: la
# lastra e' alta ~72px (texture 226x256 scalata a 64 di larghezza), quindi
# con off 64 spunta solo 4px nella cella del passaggio.
const WALL_OPEN_OFF: float = 64.0
const WALL_CLOSED_OFF: float = 16.0
const WALL_SLAM_SPEED: float = 520.0
const WALL_JITTER: float = 2.5


# ===========================================================================
# GENERAZIONE
# ===========================================================================

## Rigenera gli hazard per il livello. Chiamato da start_level DOPO
## _spawn_collectibles (le celle occupate da item sono escluse). Il seed
## dipende solo dal livello: al continue gli hazard tornano nelle stesse
## celle con stati freschi (semplificazione voluta).
func generate(level: int, maze: Node, ctrl: Node) -> void:
        controller = ctrl
        clear(maze)
        var count: int = C.hazard_count_for_level(level)
        if count <= 0:
                return
        _rng.seed = hash("hazards_v1_%d" % level)

        var floor_cells := _collect_floor_cells(maze)
        var wall_cells := _collect_wall_cells(maze)
        var used: Array[Vector2i] = []

        for t in [HazardType.QUICKSAND, HazardType.TRAP, HazardType.CHASM]:
                for _i in count:
                        var cell := _pop_cell(floor_cells, used, maze)
                        if cell == Vector2i(-1, -1):
                                break
                        _spawn_floor_hazard(t, cell, maze)
                        used.append(cell)

        for _i in count:
                var cell := _pop_cell(wall_cells, used, maze)
                if cell == Vector2i(-1, -1):
                        break
                _spawn_rock_wall(cell, maze)
                used.append(cell)


## Rimuove tutto e ripristina lo stato di Maze/BG.
func clear(maze: Node) -> void:
        for h in hazard_list:
                if is_instance_valid(h.get("sprite")):
                        h["sprite"].queue_free()
                for key in ["slab_a", "slab_b"]:
                        if is_instance_valid(h.get(key)):
                                h[key].queue_free()
        hazard_list.clear()
        if maze != null:
                maze.dynamic_walls.clear()


## Rimuove gli hazard su una cella (es. cella della porta di uscita che
## diventa attiva, o muro interno rotto dal Mjolnir).
func clear_at(cell: Vector2i, maze: Node) -> void:
        for i in range(hazard_list.size() - 1, -1, -1):
                if hazard_list[i]["cell"] == cell:
                        var h: Dictionary = hazard_list[i]
                        if is_instance_valid(h.get("sprite")):
                                h["sprite"].queue_free()
                        for key in ["slab_a", "slab_b"]:
                                if is_instance_valid(h.get(key)):
                                        h[key].queue_free()
                        hazard_list.remove_at(i)
                        maze.dynamic_walls.erase(_wall_key(cell))


# --- candidate cells -------------------------------------------------------

## Celle EMPTY valide per hazard da pavimento: corridoi, lontane dallo
## spawn (1,1), non tunnel e non adiacenti agli imbocchi, non occupate da
## collectible a terra, con rispetto del gap minimo tra hazard (nel pop).
func _collect_floor_cells(maze: Node) -> Array[Vector2i]:
        var cells: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        if _near_tunnel(c, r):
                                continue
                        if max(absi(c - 1), absi(r - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                                continue
                        if controller != null \
                                        and not controller._collectible_cell_free(c, r):
                                continue
                        cells.append(Vector2i(c, r))
        return cells


## Celle WALL con ESATTAMENTE due vicini aperti OPPOSTI (E+W oppure N+S):
## sono le pareti sottili tra due corridoi — le scorciatoie vere. Bordi e
## adiacenze tunnel escluse.
func _collect_wall_cells(maze: Node) -> Array[Vector2i]:
        var cells: Array[Vector2i] = []
        for r in range(1, C.MAZE_ROWS - 1):
                for c in range(1, C.MAZE_COLS - 1):
                        if maze.get_cell_type(c, r) != C.CellType.WALL:
                                continue
                        if _near_tunnel(c, r):
                                continue
                        if max(absi(c - 1), absi(r - 1)) < C.HAZARD_MIN_SPAWN_DIST:
                                continue
                        var ew_open: bool = not maze.is_wall(c - 1, r) \
                                        and not maze.is_wall(c + 1, r)
                        var ns_open: bool = not maze.is_wall(c, r - 1) \
                                        and not maze.is_wall(c, r + 1)
                        # esattamente due vicini aperti e opposti: una delle
                        # coppie e' aperta E le altre due direzioni son muri
                        var open_n: int = int(not maze.is_wall(c - 1, r)) \
                                        + int(not maze.is_wall(c + 1, r)) \
                                        + int(not maze.is_wall(c, r - 1)) \
                                        + int(not maze.is_wall(c, r + 1))
                        if open_n != 2:
                                continue
                        if not (ew_open or ns_open):
                                continue
                        cells.append(Vector2i(c, r))
        return cells


func _near_tunnel(c: int, r: int) -> bool:
        for tc in C.TUNNEL_COLS_TOP_BOTTOM:
                if absi(c - tc) <= 1 and (r <= 2 or r >= C.MAZE_ROWS - 3):
                        return true
        # riga tunnel laterale: celle della riga e le due adiacenti
        if absi(r - C.TUNNEL_ROW_SIDES) <= 1 and (c <= 2 or c >= C.MAZE_COLS - 3):
                return true
        return false


## Estrae una cella casuale che rispetti il gap minimo dagli hazard gia'
## piazzati (Manhattan >= HAZARD_MIN_GAP).
func _pop_cell(cells: Array[Vector2i], used: Array[Vector2i], _maze: Node) -> Vector2i:
        for _attempt in 24:
                if cells.is_empty():
                        break
                var idx: int = _rng.randi_range(0, cells.size() - 1)
                var cell: Vector2i = cells[idx]
                var ok := true
                for u in used:
                        if absi(cell.x - u.x) + absi(cell.y - u.y) < C.HAZARD_MIN_GAP:
                                ok = false
                                break
                if ok:
                        cells.remove_at(idx)
                        return cell
                cells.remove_at(idx)
        return Vector2i(-1, -1)


# --- spawn dei singoli hazard ----------------------------------------------

func _cell_center(cell: Vector2i) -> Vector2:
        return Vector2(
                cell.x * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                cell.y * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)


func _tex(path: String) -> Texture2D:
        if not _tex_cache.has(path):
                _tex_cache[path] = load(path)
        return _tex_cache[path]


func _make_sprite(tex_path: String, cell: Vector2i, px: float = C.TILE_SIZE) -> Sprite2D:
        var s := Sprite2D.new()
        s.texture = _tex(tex_path)
        s.position = _cell_center(cell)
        s.scale = Vector2(px / s.texture.get_width(), px / s.texture.get_height())
        # z_index 0 (default): l'ordine dell'albero MainGame fa il resto —
        # Maze (pavimento) -> Hazards -> Player/Enemies. Con z_index -1 gli
        # sprite finivano DIETRO il pavimento del Maze (_draw a z=0) e
        # risultavano invisibili.
        s.z_index = 0
        add_child(s)
        return s


func _spawn_floor_hazard(t: int, cell: Vector2i, maze: Node) -> void:
        var h: Dictionary = {"type": t, "cell": cell}
        match t:
                HazardType.QUICKSAND:
                        h["sprite"] = _make_sprite(
                                "res://assets/sprites/hazards/quicksand.png", cell, 66.0)
                HazardType.TRAP:
                        h["state"] = TrapState.ARMED
                        h["timer_ms"] = 0.0
                        h["holding"] = null
                        h["hold_ms"] = 0.0
                        h["sprite"] = _make_sprite(
                                "res://assets/sprites/hazards/trap_armed.png", cell, 62.0)
                HazardType.CHASM:
                        # apertura differita casuale: le voragini NON
                        # appaiono tutte nello stesso istante
                        h["state"] = ChasmState.DORMANT
                        h["timer_ms"] = float(_rng.randi_range(500, 6000))
                        h["sprite"] = null  # sprite creato al CRACK
        hazard_list.append(h)


func _spawn_rock_wall(cell: Vector2i, maze: Node) -> void:
        var ew_open: bool = not maze.is_wall(cell.x - 1, cell.y) \
                        and not maze.is_wall(cell.x + 1, cell.y)
        var h: Dictionary = {
                "type": HazardType.ROCK_WALL,
                "cell": cell,
                "axis": "h" if ew_open else "v",
                "phase": WallPhase.OPEN,
                # fase iniziale sfasata: i muri non battono all'unisono
                "phase_ms": float(_rng.randi_range(0, C.HAZARD_WALL_OPEN_MS)),
                "off_a": WALL_OPEN_OFF,
                "off_b": WALL_OPEN_OFF,
        }
        var tex := "res://assets/sprites/hazards/rock_slab.png"
        h["slab_a"] = _make_sprite(tex, cell, 0.0)  # scala sistemata sotto
        h["slab_b"] = _make_sprite(tex, cell, 0.0)
        # ogni meta' copre l'intera cella (64x64); per un passaggio
        # orizzontale scivolano da sopra/sotto (la B capovolta si incastra
        # nella A). Passaggio verticale: ruotate di 90 gradi.
        # FIX (divisione intera): TILE_SIZE e get_width() sono INT -> 64/226
        # faceva 0 e la scala collassava a 1e-5 (lastre invisibili). Cast a
        # float PRIMA della divisione.
        var s: float = float(C.TILE_SIZE) / float(h["slab_a"].texture.get_width())
        for key in ["slab_a", "slab_b"]:
                h[key].scale = Vector2(s, s)
                if h["axis"] == "v":
                        h[key].rotation = PI / 2.0
        h["slab_b"].flip_v = true
        hazard_list.append(h)
        _apply_wall_offsets(h)
        # registrazione nel Maze: la cella e' un muro DINAMICO attualmente
        # APERTO (attraversabile). is_wall() da qui in poi consulta il
        # registro, non il tipo statico.
        maze.dynamic_walls[_wall_key(cell)] = false


func _wall_key(cell: Vector2i) -> String:
        return "%d,%d" % [cell.x, cell.y]


func _apply_wall_offsets(h: Dictionary) -> void:
        var center: Vector2 = _cell_center(h["cell"])
        var a: Sprite2D = h["slab_a"]
        var b: Sprite2D = h["slab_b"]
        if h["axis"] == "h":
                a.position = center + Vector2(0.0, -float(h["off_a"]))
                b.position = center + Vector2(0.0, float(h["off_b"]))
        else:
                a.position = center + Vector2(-float(h["off_a"]), 0.0)
                b.position = center + Vector2(float(h["off_b"]), 0.0)


# ===========================================================================
# UPDATE
# ===========================================================================

## Chiamato da MainGameController._update_playing DOPO l'update dei player
## e PRIMA di quello dei nemici: le celle occupate sono fresche, i flag
## held_by_wall sono gia' validi per il movimento nemico del frame stesso.
func update_hazards(delta_ms: float, maze: Node) -> void:
        if not C.HAZARDS_ENABLED or hazard_list.is_empty():
                _reset_players_flags()
                return
        _time += delta_ms / 1000.0
        var players: Array = _active_players()

        for h in hazard_list:
                match h["type"]:
                        HazardType.QUICKSAND:
                                _update_quicksand(h)
                        HazardType.TRAP:
                                _update_trap(h, delta_ms, players, maze)
                        HazardType.CHASM:
                                _update_chasm(h, delta_ms, players, maze)
                        HazardType.ROCK_WALL:
                                _update_rock_wall(h, delta_ms, maze)

        # Mjolnir: se la cella muro non e' piu' WALL (spezzata), il muro di
        # roccia si sgretola e despawna.
        for i in range(hazard_list.size() - 1, -1, -1):
                var h: Dictionary = hazard_list[i]
                if h["type"] == HazardType.ROCK_WALL \
                                and maze.get_cell_type(h["cell"].x, h["cell"].y) != C.CellType.WALL:
                        _poof_wall(h)
                        hazard_list.remove_at(i)

        _update_players_slow(players, maze)


func _reset_players_flags() -> void:
        if controller == null:
                return
        for p in _active_players():
                p.hazard_slow = 1.0
                p.held_by_wall = false
                if p.held_by_trap and not _trap_holding(p):
                        p.held_by_trap = false


func _trap_holding(_p: CharacterBody2D) -> bool:
        for h in hazard_list:
                if h["type"] == HazardType.TRAP and h.get("holding") == _p:
                        return true
        return false


func _active_players() -> Array:
        var out: Array = []
        if controller == null:
                return out
        var p1: CharacterBody2D = controller.player
        if p1 != null and p1.visible and not p1.soul_pending:
                out.append(p1)
        if controller.player2 != null and controller.player2.visible \
                        and not controller.player2.soul_pending:
                out.append(controller.player2)
        return out


func _player_cell(p: CharacterBody2D) -> Vector2i:
        return Vector2i(
                int(p.position.x / C.TILE_SIZE),
                int((p.position.y - C.UI_HEIGHT) / C.TILE_SIZE))


## Un player e' "grounded" sulla cella se NON sta saltando (il salto e'
## l'arco che copre l'intera cella: pattern "salto sopra le armi").
func _player_grounded(p: CharacterBody2D) -> bool:
        return not p.is_jumping() and not p.is_ghost()


# --- quicksand --------------------------------------------------------------

func _update_quicksand(h: Dictionary) -> void:
        # vortice lento: rotazione continua + respiro di scala
        var s: Sprite2D = h["sprite"]
        s.rotation += 0.25 * (_time - float(h.get("last_t", 0.0)))
        h["last_t"] = _time
        var k: float = 1.0 + 0.04 * sin(_time * 2.0)
        s.scale = Vector2(66.0 / s.texture.get_width(), 66.0 / s.texture.get_height()) * k


func _update_players_slow(players: Array, maze: Node) -> void:
        for p in players:
                var slow: float = 1.0
                if p.held_by_trap or p.held_by_wall:
                        slow = 1.0
                elif not p.is_ghost() and not p.is_jumping():
                        var cell := _player_cell(p)
                        for h in hazard_list:
                                if h["type"] == HazardType.QUICKSAND \
                                                and h["cell"] == cell:
                                        # STIVALI ALATI (speed boots): chi vola
                                        # non affonda — il malus e' annullato.
                                        if p.permanent_speed_boost:
                                                slow = 1.0
                                        else:
                                                slow = C.HAZARD_QUICKSAND_SLOW
                                        break
                p.hazard_slow = slow


# --- trap -------------------------------------------------------------------

func _update_trap(h: Dictionary, delta_ms: float, players: Array, _maze: Node) -> void:
        match h["state"]:
                TrapState.ARMED:
                        # disarmo: proiettile di qualunque player nella cella
                        if _projectile_in_cell(h["cell"], players):
                                _snap_trap(h, null, false)
                                return
                        # cattura: player grounded nella cella
                        for p in players:
                                if _player_grounded(p) \
                                                and _player_cell(p) == h["cell"] \
                                                and not p.held_by_trap:
                                        _snap_trap(h, p, true)
                                        return
                TrapState.SNAPPED:
                        var victim: CharacterBody2D = h["holding"]
                        if victim != null:
                                # morte/teletrasporto della vittima: libera
                                if not is_instance_valid(victim) \
                                                or not victim.visible \
                                                or _player_cell(victim) != h["cell"]:
                                        _release_trap(h, C.HAZARD_TRAP_REARM_MS)
                                        return
                                # mash: ogni pressione consumata accorcia
                                var mash: int = victim.input_mash_count
                                if mash > 0:
                                        victim.input_mash_count = 0
                                        h["hold_ms"] = maxf(
                                                C.HAZARD_TRAP_HOLD_MIN_MS,
                                                h["hold_ms"] - C.HAZARD_TRAP_MASH_REDUCE_MS * mash)
                                # tieni il player agganciato al centro
                                var center: Vector2 = _cell_center(h["cell"])
                                victim.position = victim.position.move_toward(
                                        center, 3.0 * delta_ms / 16.6667)
                                victim.held_by_trap = true
                                h["hold_ms"] -= delta_ms
                                if h["hold_ms"] <= 0.0:
                                        _release_trap(h, C.HAZARD_TRAP_REARM_MS)
                        else:
                            # scatto a vuoto (disarmo): riarmo piu' corto
                            # (gestito in _snap_trap con timer REARM)
                            pass
                TrapState.REARM:
                        h["timer_ms"] -= delta_ms
                        if h["timer_ms"] <= 0.0:
                                h["state"] = TrapState.ARMED
                                _set_trap_sprite(h, true)
        # NOTA: il parametro maze non e' usato qui (le ganasce non toccano
        # i muri), resta nella firma per simmetria con gli altri update.


func _snap_trap(h: Dictionary, victim: CharacterBody2D, with_player: bool) -> void:
        if AudioManager:
                if with_player:
                        AudioManager.play_sound(AudioManager.SoundType.HAZARD_SNAP)
                else:
                        AudioManager.play_sound(AudioManager.SoundType.HAZARD_DISARM)
        _set_trap_sprite(h, false)
        if with_player and victim != null:
                h["state"] = TrapState.SNAPPED
                h["holding"] = victim
                h["hold_ms"] = float(C.HAZARD_TRAP_HOLD_MS)
                victim.held_by_trap = true
                victim.dx = 0
                victim.dy = 0
                # danno ambientale: 33% energia max, BYPASS armature
                var dmg: int = maxi(1, int(round(
                        victim.max_energy * C.HAZARD_TRAP_DAMAGE_PCT)))
                victim.take_hazard_damage(dmg)
                if EffectsManager:
                        EffectsManager.screen_shake(5.0, 0.3)
                        var sp := EffectsManager.spawn_sparks(_cell_center(h["cell"]), 10)
                        if controller != null:
                                controller.collectibles_node.add_child(sp)
                # se il danno ha ucciso, il player e' gia' respawnato allo
                # spawn: la trap si libera al prossimo giro (_player_cell != cell)
        else:
                h["state"] = TrapState.REARM
                h["timer_ms"] = float(C.HAZARD_TRAP_DISARM_REARM_MS)
                h["holding"] = null


func _release_trap(h: Dictionary, rearm_ms: int) -> void:
        var victim: CharacterBody2D = h["holding"]
        if victim != null and is_instance_valid(victim):
                victim.held_by_trap = false
        h["holding"] = null
        h["state"] = TrapState.REARM
        h["timer_ms"] = float(rearm_ms)


func _set_trap_sprite(h: Dictionary, armed: bool) -> void:
        var path: String = "res://assets/sprites/hazards/trap_armed.png" if armed \
                        else "res://assets/sprites/hazards/trap_closed.png"
        if h["sprite"] == null:
                h["sprite"] = _make_sprite(path, h["cell"], 62.0)
        else:
                h["sprite"].texture = _tex(path)


func _projectile_in_cell(cell: Vector2i, players: Array) -> bool:
        for p in players:
                for proj in p.projectiles:
                        if not proj.get("active", false):
                                continue
                        var pos: Vector2 = proj["pos"]
                        if int(pos.x / C.TILE_SIZE) == cell.x \
                                        and int((pos.y - C.UI_HEIGHT) / C.TILE_SIZE) == cell.y:
                                proj["active"] = false  # il colpo "consuma" la ganascia
                                return true
        return false


# --- chasm ------------------------------------------------------------------

func _update_chasm(h: Dictionary, delta_ms: float, players: Array, _maze: Node) -> void:
        match h["state"]:
                ChasmState.DORMANT:
                        h["timer_ms"] -= delta_ms
                        if h["timer_ms"] <= 0.0:
                                h["state"] = ChasmState.CRACK
                                h["timer_ms"] = float(C.HAZARD_CHASM_TELEGRAPH_MS)
                                h["sprite"] = _make_sprite(
                                        "res://assets/sprites/hazards/chasm_crack.png",
                                        h["cell"], 64.0)
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_RUMBLE)
                                if EffectsManager:
                                        EffectsManager.screen_shake(2.0, 0.35)
                ChasmState.CRACK:
                        h["timer_ms"] -= delta_ms
                        # lampeggio d'allerta della crepa
                        if h["sprite"] != null:
                                h["sprite"].modulate.a = 0.75 + 0.25 * sin(_time * 18.0)
                        if h["timer_ms"] <= 0.0:
                                _open_chasm(h, _maze)
                ChasmState.OPEN:
                        # chi cammina (grounded) nella cella aperta cade
                        for p in players:
                                if _player_grounded(p) \
                                                and _player_cell(p) == h["cell"]:
                                        p.fall_into_chasm()
                                        return


func _open_chasm(h: Dictionary, _maze: Node) -> void:
        h["state"] = ChasmState.OPEN
        if h["sprite"] != null:
                h["sprite"].queue_free()
        h["sprite"] = _make_sprite(
                "res://assets/sprites/hazards/chasm_open.png", h["cell"], 66.0)
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_COLLAPSE)
        if EffectsManager:
                EffectsManager.screen_shake(6.0, 0.4)
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(h["cell"]), Color(0.35, 0.3, 0.25), 14, 0.5)
                if controller != null:
                        controller.collectibles_node.add_child(dust)


# --- rock wall --------------------------------------------------------------

func _update_rock_wall(h: Dictionary, delta_ms: float, maze: Node) -> void:
        h["phase_ms"] += delta_ms
        match h["phase"]:
                WallPhase.OPEN:
                        if h["phase_ms"] >= float(C.HAZARD_WALL_OPEN_MS):
                                h["phase"] = WallPhase.WARN
                                h["phase_ms"] = 0.0
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)
                WallPhase.WARN:
                        # vibrazione pre-chiusura: le rocce strisciano verso
                        # il centro con jitter (telegrafo)
                        if h["phase_ms"] >= float(C.HAZARD_WALL_WARN_MS):
                                h["phase"] = WallPhase.CLOSED
                                h["phase_ms"] = 0.0
                                _close_wall(h, maze)
                WallPhase.CLOSED:
                        if h["phase_ms"] >= float(C.HAZARD_WALL_CLOSED_MS):
                                h["phase"] = WallPhase.OPEN
                                h["phase_ms"] = 0.0
                                maze.dynamic_walls[_wall_key(h["cell"])] = false
                                if AudioManager:
                                        AudioManager.play_sound(
                                                AudioManager.SoundType.HAZARD_GRIND)

        # inseguimento del target di offset (slam/apertura animati)
        var target: float = WALL_CLOSED_OFF if h["phase"] == WallPhase.CLOSED \
                        else WALL_OPEN_OFF
        var step: float = WALL_SLAM_SPEED * delta_ms / 1000.0
        h["off_a"] = move_toward(float(h["off_a"]), target, step)
        h["off_b"] = move_toward(float(h["off_b"]), target, step)
        # vibrazione durante il WARN
        var jitter := 0.0
        if h["phase"] == WallPhase.WARN:
                jitter = sin(_time * 60.0) * WALL_JITTER
        var save_a: float = h["off_a"]
        var save_b: float = h["off_b"]
        h["off_a"] += jitter
        h["off_b"] -= jitter
        _apply_wall_offsets(h)
        h["off_a"] = save_a
        h["off_b"] = save_b

        # flag held per player/nemici nella cella CHUSA (ricalcolo per-frame:
        # niente flag che restano appiccicati dopo respawn/morte)
        if h["phase"] == WallPhase.CLOSED:
                _hold_entities_in_wall(h, maze)
        else:
                _release_entities_in_wall(h, maze)


func _close_wall(h: Dictionary, maze: Node) -> void:
        var cell: Vector2i = h["cell"]
        maze.dynamic_walls[_wall_key(cell)] = true
        if AudioManager:
                AudioManager.play_sound(AudioManager.SoundType.HAZARD_THUD)
        if EffectsManager:
                EffectsManager.screen_shake(7.0, 0.35)
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(cell), Color(0.4, 0.35, 0.3), 18, 0.6)
                if controller != null:
                        controller.collectibles_node.add_child(dust)

        # player nella cella alla chiusura: danno 66% (se non airborne) e
        # imprigionamento fino alla riapertura
        for p in _active_players():
                if _player_cell(p) == cell:
                        p.held_by_wall = true
                        var dmg: int = maxi(1, int(round(
                                p.max_energy * C.HAZARD_WALL_PLAYER_DAMAGE_PCT)))
                        p.take_hazard_damage(dmg)

        # nemici nella cella: 33% HP max, bloccati finche' chiuso; ucciso
        # dal muro = 2x punti al player vivo piu' vicino
        if controller == null:
                return
        for e in controller.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead():
                        continue
                var ecell := Vector2i(
                        int(e.position.x / C.TILE_SIZE),
                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                if ecell != cell:
                        continue
                var dmg: int = maxi(1, int(round(
                        e.get_max_health() * C.HAZARD_WALL_ENEMY_DAMAGE_PCT)))
                e.take_damage(dmg)
                if e.is_dead():
                        var winner := _nearest_player(e.position)
                        if winner != null:
                                winner.add_score(C.HAZARD_WALL_KILL_POINTS)
                        if EffectsManager:
                                var blood := EffectsManager.spawn_blood(
                                        e.position, 18)
                                controller.collectibles_node.add_child(blood)
                else:
                        e.held_by_wall = true


func _hold_entities_in_wall(h: Dictionary, _maze: Node) -> void:
        var cell: Vector2i = h["cell"]
        for p in _active_players():
                if _player_cell(p) == cell:
                        p.held_by_wall = true
        if controller != null:
                for e in controller.spawner.enemies:
                        if e != null and is_instance_valid(e) and not e.is_dead():
                                var ecell := Vector2i(
                                        int(e.position.x / C.TILE_SIZE),
                                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                if ecell == cell:
                                        e.held_by_wall = true


func _release_entities_in_wall(h: Dictionary, _maze: Node) -> void:
        # il rilascio e' per-cellula: libera SOLO chi e' nella cella di
        # QUESTO muro (altri muri chiusi devono continuare a tenere)
        var cell: Vector2i = h["cell"]
        for p in _active_players():
                if p.held_by_wall and _player_cell(p) == cell:
                        p.held_by_wall = false
        if controller != null:
                for e in controller.spawner.enemies:
                        if e != null and is_instance_valid(e) \
                                        and e.held_by_wall:
                                var ecell := Vector2i(
                                        int(e.position.x / C.TILE_SIZE),
                                        int((e.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                if ecell == cell:
                                        e.held_by_wall = false


func _nearest_player(from_pos: Vector2) -> CharacterBody2D:
        var best: CharacterBody2D = null
        var best_d: float = INF
        for p in _active_players():
                var d: float = p.position.distance_squared_to(from_pos)
                if d < best_d:
                        best_d = d
                        best = p
        return best


func _poof_wall(h: Dictionary) -> void:
        if is_instance_valid(h.get("slab_a")):
                h["slab_a"].queue_free()
        if is_instance_valid(h.get("slab_b")):
                h["slab_b"].queue_free()
        if EffectsManager and controller != null:
                var dust := EffectsManager.spawn_explosion(
                        _cell_center(h["cell"]), Color(0.4, 0.35, 0.3), 14, 0.5)
                controller.collectibles_node.add_child(dust)


# ===========================================================================
# QUERY (per test e debug)
# ===========================================================================

func count_by_type(t: int) -> int:
        var n := 0
        for h in hazard_list:
                if h["type"] == t:
                        n += 1
        return n


func find_first(t: int) -> Dictionary:
        for h in hazard_list:
                if h["type"] == t:
                        return h
        return {}

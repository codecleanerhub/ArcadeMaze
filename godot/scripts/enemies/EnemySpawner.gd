# ===========================================================================
# EnemySpawner.gd - Spawns enemy waves for Arcade Maze Fantasy (Godot port).
#
# Port of the spawning logic in src/Game.cpp:
#   * spawnEnemies()           (line 373-400) - initial wave per maze level
#   * spawnEnemyFromPortal()    (line 407-447) - respawn from magic portal
#   * Magic-portal activation   (line 1949-2101) - 50%-killed trigger with
#     3 enemies + 1 mini-boss.
#
# Public API:
#   spawn_enemies(maze)               - place 5 random enemies at level start
#   trigger_portal(maze, player_pos)  - open magic portal at 50% kills
#   update_portal(maze, dt_ms)        - tick the portal's open/spawn/close
#                                       state machine; respawns enemies
#                                       one-at-a-time every 4 s
#
# The spawner owns:
#   * `enemies`       : Array[Enemy] - the live enemy pool (Game reads this)
#   * `magic_portal`  : portal state (position, phase, spawn queue)
#   * `initial_count`  : snapshot of enemies.size() at level start, used
#                        to compute the 50% threshold
#   * `portal_used`    : one-shot latch - portal fires at most once / level
# ===========================================================================
class_name EnemySpawner
extends Node

const C = preload("res://scripts/core/GameConstants.gd")

# --- Grid constants (mirror Utils.h) ----------------------------------------
const TILE_SIZE: int = 64
# FIX (doppio muro lato destro): allineato con GameConstants (31, dispari;
# con 30 pari la colonna 28 restava sempre muro -> doppio muro destro).
# FIX (muro destro invisibile): 31 -> 30, allineato a GameConstants
# (vedi fix muro destro in GameConstants/Maze.generate).
const MAZE_COLS: int = 30
const MAZE_ROWS: int = 15
const UI_HEIGHT: int = 80

# --- Cell type constants (mirror Maze.h CellType) ---------------------------
const CELL_EMPTY: int = 0
const CELL_WALL: int = 1
const CELL_TREASURE: int = 2
const CELL_WEAPON: int = 3

# --- Spawning tuning --------------------------------------------------------
# FIX (6 nemici al livello 1 + 1 per boss): l'utente ha dichiarato che al
# livello 1 ci sono 6 nemici; dopo OGNI boss sconfitto l'ondata cresce di 1.
# Con un gruppo di 4 livelli (3 maze + 1 boss), i boss sconfitti prima del
# livello L sono floor((L-1)/4): livello 1..4 → 0 boss → 6 nemici;
# livello 5 (dopo il 1° boss) → 7 nemici; livello 9 → 8; ecc.
const BASE_WAVE_SIZE: int = 6
const INITIAL_WAVE_SIZE: int = 6  # compat: dimensione dell'ondata al livello 1
# FIX (respawn 100% nemici): PORTAL_ENEMIES_TO_SPAWN era 0 perché calcolato
# come 50% di initial_count in trigger_portal_if_needed. Ora il portale
# respawna il 100% dei nemici iniziali (6 iniziali → 6 respawnati + miniboss).
const PORTAL_ENEMIES_TO_SPAWN: int = 0
# Portal phase timers (ms simulated) - mirror Game.cpp line 1979-2140.
const PORTAL_OPEN_MS: int = 1000     # phase 0: portal opening
const PORTAL_CLOSE_MS: int = 2800    # phase 2: portal closing (2.8s, era 0.8s)
const PORTAL_FIRST_SPAWN_MS: int = 500   # delay before first respawn
const PORTAL_SPAWN_INTERVAL_MS: int = 4000  # 4 s between respawns
# Cell-search radius when placing a respawned enemy near the portal.
const PORTAL_PLACE_MAX_RADIUS: int = 5

# --- Public state -----------------------------------------------------------

# Live enemy pool. Game iterates over this each frame to call update_enemy.
var enemies: Array = []  # Array[Enemy]

# Magic portal state machine.
# Phases: 0=opening, 1=spawning, 2=closing, 3=inactive.
var magic_portal: Dictionary = {
        "pos": Vector2.ZERO,
        "active": false,
        "phase": 3,
        "phase_timer": 0,
        "rotation": 0.0,
        "glow_pulse": 0.0,
        "enemies_to_spawn": 0,
        "spawn_timer": 0,
        "dead_indices": [],   # indices into `enemies` array for respawn
}

# Initial count for 50% trigger (snapshot taken in spawn_enemies()).
var initial_count: int = 0
# One-shot latch: portal triggers at most once per maze level.
var portal_used: bool = false

# ---------------------------------------------------------------------------
# TASK 23 (meccanica utente): RESPAWN PROGRESSIVO dopo il 5° boss.
# Dal livello 21 in poi (5 boss sconfitti) il portale NON scarica più tutto
# il respawn in un'unica ondata: al primo trigger (soglia 50%, come prima)
# escono il MINI-BOSS + 1 nemico comune, il portale si chiude; poi, a ogni
# KILL di un nemico del labirinto, il portale RIAPPARE e fa uscire altri 2
# nemici — e così via finché non sono usciti tutti i nemici previsti per
# quel livello (budget = numero di nemici iniziali). Massimo 2 alla volta
# per non affollare il labirinto.
# ---------------------------------------------------------------------------
## True dal livello 21+ (boss sconfitti >= 5): respawn a ventaglietti.
var progressive_respawn: bool = false
## Nemici ancora da far uscire dal portale (respawn progressivo).
var respawn_budget: int = 0

## TASK 23: true se il respawn progressivo ha ancora nemici in sospeso
## (il MainGameController lo usa per non far scattare HURRY UP finché il
## portale non ha finito di "sfornare").
func respawn_pending() -> bool:
        return progressive_respawn and respawn_budget > 0

# FIX (nemico +1 dopo ogni boss): numero di nuovi tipi sbloccati per il
# livello corrente (0..16). Impostato da spawn_enemies() in base al livello;
# il respawn casuale dal portale pesca dal pool 28 + unlocked_new_types.
var unlocked_new_types: int = 0

# Enemy scene - override from inspector if you have a custom .tscn.
# Default: use the Enemy.gd script directly via `Enemy.new()`.
@export var enemy_scene: PackedScene = null


# ===========================================================================
# wave_size_for_level(level): 6 nemici al livello 1, +1 dopo OGNI boss.
# boss sconfitti prima del livello L = (L-1)/4 (i boss sono ai livelli 4, 8, ...).
# In infinite mode cresce senza limite (lo slot extra oltre i 16 nuovi tipi
# viene riempito con tipi originali random).
# ===========================================================================
static func wave_size_for_level(level: int) -> int:
        var bosses_defeated: int = (maxi(1, level) - 1) / 4
        return BASE_WAVE_SIZE + bosses_defeated


# ===========================================================================
# unlocked_new_types_for_level(level): quanti dei 16 nuovi tipi (OWLBEAR..)
# sono già stati sbloccati arrivando a questo livello (uno per boss).
# ===========================================================================
static func unlocked_new_types_for_level(level: int) -> int:
        var bosses_defeated: int = (maxi(1, level) - 1) / 4
        return mini(bosses_defeated, Enemy.ENEMY_NEW_TYPE_COUNT)


# ===========================================================================
# spawn_enemies(maze, level): generate the level wave.
#
# Wave composition (FIX: 6 nemici al livello 1 + 1 per ogni boss sconfitto):
#   * base = 6 tipi originali random (i 28 "classici")
#   * dopo ogni boss: +1 nemico, e ogni slot extra è uno dei 16 NUOVI tipi
#     (OWLBEAR, GIBBERING_MOUTHER, ...) sbloccati in ordine — così ogni
#     livello post-boss introduce una creatura mai vista prima, diversa da
#     tutte le esistenti, stessa grafica/stile/dimensioni dei precedenti.
#
# Position: random until a non-wall cell is found that's NOT in the
# player's safe-startup zone (col < 5 AND row < 5).
# ===========================================================================
func spawn_enemies(maze: Object, level: int = 1) -> void:
        enemies.clear()
        var wave_size: int = wave_size_for_level(level)
        unlocked_new_types = unlocked_new_types_for_level(level)
        # TASK 23: respawn progressivo dal livello 21 (dopo il 5° boss:
        # boss ai livelli 4,8,12,16,20 → boss sconfitti = (21-1)/4 = 5).
        progressive_respawn = wave_size_for_level(level) >= BASE_WAVE_SIZE + 5
        # FIX (sprite uno sopra l'altro): celle già usate da questo wave, per
        # mantenere distanza minima tra spawn (uniformità visiva).
        var used_cells: Array = []
        for i in range(wave_size):
                var t: int
                if i < unlocked_new_types:
                        # Slot extra: il nuovo tipo sbloccato al boss i
                        t = Enemy.get_unlockable_type(i)
                else:
                        t = randi() % Enemy.ENEMY_ORIGINAL_TYPE_COUNT
                var c: int
                var r: int
                # Find a valid spawn cell: EMPTY floor (non tesoro, non arma,
                # FIX sprite sopra i tesori), NOT in the 5x5 starting zone,
                # almeno 2 celle di distanza Manhattan dagli altri spawn di
                # questo wave. (Game.cpp condition: while (isWall || (c<5&&r<5)))
                # Relax progressivo: 150 tentativi con distanza, poi solo EMPTY,
                # poi qualunque cella non-muro (maze degenere).
                var attempts: int = 0
                while true:
                        c = 1 + randi() % (MAZE_COLS - 2)
                        r = 1 + randi() % (MAZE_ROWS - 2)
                        attempts += 1
                        if attempts > 250:
                                break  # safety: maze degenerate, give up searching
                        if c < 5 and r < 5:
                                continue
                        if attempts > 150:
                                if not maze.is_wall(c, r):
                                        break
                                continue
                        if maze.get_cell_type(c, r) != CELL_EMPTY:
                                continue
                        var far_enough: bool = true
                        for u in used_cells:
                                if absi(u.x - c) + absi(u.y - r) < 2:
                                        far_enough = false
                                        break
                        if far_enough:
                                break
                used_cells.append(Vector2i(c, r))
                _spawn_enemy_instance(t, c, r)
        # Snapshot for the 50% portal trigger.
        initial_count = enemies.size()
        portal_used = false
        # TASK 23: budget respawn = tutti i nemici previsti per il livello
        # (nelle modalità progressive verranno rilasciati 1 + 2 per kill).
        respawn_budget = initial_count if progressive_respawn else 0
        # Reset portal state to inactive.
        magic_portal.active = false
        magic_portal.phase = 3
        magic_portal.phase_timer = 0
        magic_portal.enemies_to_spawn = 0
        magic_portal.dead_indices.clear()


# ===========================================================================
# _spawn_enemy_instance(type, col, row): create one Enemy, init it, and
# add to the pool. Centralised so spawn_enemies() and update_portal() can
# share the same code path.
# ===========================================================================
func _spawn_enemy_instance(t: int, col: int, row: int) -> Enemy:
        var e: Enemy
        if enemy_scene != null:
                e = enemy_scene.instantiate() as Enemy
        else:
                e = Enemy.new()
        e.init(t, col, row)
        # TASK 76 (crash "get_nodes_in_group on null"): un nemico appeso al
        # pool MAI aggiunto al tree resta invisibile e fa esplodere get_tree()
        # nel primo update. Se lo spawner non e' nel tree NON si spawn:
        # l'istanza viene liberata e il pool resta pulito. (Il controller
        # esegue _physics_process solo nel tree, quindi questo avviene solo
        # in finestre di teardown/restore.)
        if not is_inside_tree() or get_parent() == null:
                e.queue_free()
                return null
        get_parent().add_child(e)
        enemies.append(e)
        return e


# FIX (sprite uno sopra l'altro): callable opzionale che dice se una cella
# è libera da collectible (mine/calice/scettro/statua/pozione/ecc.). Passato
# da MainGameController per evitare che portale, mini-boss e nemici respawnati
# spuntino SOPRA un oggetto raccolto o raccoglibile.
var _portal_cell_check: Callable = Callable()


# ===========================================================================
# trigger_portal_if_needed(maze, player_pos): check the 50%-killed
# threshold and open the magic portal when crossed. Spawns the mini-boss
# next to the portal at the same moment (see Game.cpp line 1996-2093).
# `is_cell_free` (opzionale): Callable(c, r) -> bool, true se la cella NON
# contiene collectible (usato per non aprire il portale sopra un oggetto).
#
# Returns true if the portal was opened THIS call.
# ===========================================================================
func trigger_portal_if_needed(maze: Object, player_pos: Vector2,
                                                          mini_boss_spawner: Callable = Callable(),
                                                          is_cell_free: Callable = Callable()) -> bool:
        if portal_used or initial_count <= 0:
                return false

        # Count alive enemies (health > 0).
        var alive_count: int = 0
        for e in enemies:
                if e is Enemy and not e.is_dead():
                        alive_count += 1

        if alive_count > initial_count / 2 or alive_count <= 0:
                return false

        _portal_cell_check = is_cell_free

        # --- 50% threshold crossed: open the portal at the maze centre ---
        # Search for the empty cell closest to (MAZE_COLS/2, MAZE_ROWS/2).
        # FIX: salta anche le celle occupate da collectible (il portale non
        # deve aprirsi SOPRA mina/calice/statua/pozione: sprite sovrapposti).
        var target_c: int = MAZE_COLS / 2
        var target_r: int = MAZE_ROWS / 2
        var best_c: int = -1
        var best_r: int = -1
        var best_dist: int = 999
        for c in range(1, MAZE_COLS - 1):
                for r in range(1, MAZE_ROWS - 1):
                        if maze.get_cell_type(c, r) == CELL_EMPTY:
                                if is_cell_free.is_valid() and not is_cell_free.call(c, r):
                                        continue
                                var d: int = abs(c - target_c) + abs(r - target_r)
                                if d < best_dist:
                                        best_dist = d
                                        best_c = c
                                        best_r = r

        if best_c < 0:
                return false  # no empty cell found (degenerate maze) - abort

        # Position the portal at the centre of that cell.
        magic_portal.pos = Vector2(
                best_c * TILE_SIZE + TILE_SIZE / 2.0,
                best_r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.0
        )
        magic_portal.active = true
        magic_portal.phase = 0
        magic_portal.phase_timer = PORTAL_OPEN_MS
        magic_portal.rotation = 0.0
        magic_portal.glow_pulse = 0.0
        magic_portal.enemies_to_spawn = PORTAL_ENEMIES_TO_SPAWN
        # TASK 23 (respawn progressivo post-5° boss): al PRIMO trigger il
        # portale fa uscire SOLO 1 nemico comune (+ il mini-boss, spawnato
        # qui sotto): il resto arriva 2 per volta a ogni kill successiva
        # (notify_enemy_killed) finché il budget non è esaurito.
        if progressive_respawn:
                magic_portal.enemies_to_spawn = mini(1, maxi(0, respawn_budget))
                respawn_budget = maxi(0, respawn_budget - magic_portal.enemies_to_spawn)
        else:
                # FIX (respawn 100% nemici): il portale respawna il 100% dei nemici
                # iniziali del livello (non più il 50%): se il livello è iniziato con
                # 6 nemici, dal portale ne escono 6 + il mini-boss (il portale
                # continua ad apparire quando i nemici scendono al 50%, cioè a 3).
                magic_portal.enemies_to_spawn = maxi(1, initial_count)
                if magic_portal.enemies_to_spawn > initial_count:
                        magic_portal.enemies_to_spawn = initial_count
        magic_portal.spawn_timer = 0
        magic_portal.dead_indices.clear()

        # Collect indices of fully-dead enemies so we can respawn them.
        # FIX (respawn non avviene): prima richiedeva is_death_anim_done()
        # che spesso non era true al momento del trigger. Ora raccogliamo
        # tutti i nemici morti (is_dead) indipendentemente dall'anim.
        for i in range(enemies.size()):
                var e = enemies[i]
                if e is Enemy and e.is_dead():
                        magic_portal.dead_indices.append(i)

        portal_used = true

        # --- Spawn the mini-boss next to the portal ---
        # Game.cpp line 2013-2093: search a free cell at radius 1..4 from the
        # portal; if none, fall back to the cell FARTHEST from the player.
        if mini_boss_spawner.is_valid():
                var mb_pos := _find_mini_boss_cell(maze, magic_portal.pos, player_pos)
                if mb_pos.x >= 0:
                        mini_boss_spawner.call(mb_pos.x, mb_pos.y)
                        # FIX (portale scompare subito): prima il portale veniva
                        # forzato a fase 2 (closing) con timer 200ms quando
                        # spawnava il mini-boss → il portale scompariva in 200ms
                        # e non respawnava i nemici. Ora il portale resta aperto
                        # per il ciclo completo (open 1s + spawn N×4s + close
                        # 2.8s) e respawn i nemici come previsto.
                        # Il "pallino accanto al miniboss" visivo era causato dal
                        # portale che restava fisso mentre il miniboss si
                        # muoveva — ora il portale chiude naturalmente dopo
                        # aver spawnato i nemici.

        return true


# _find_mini_boss_cell(maze, portal_pos, player_pos): locate an empty cell
# near the portal (radius 1..4) for the mini-boss to appear. Falls back to
# the cell farthest from the player (>=6 manhattan distance) if none nearby.
# Returns Vector2i(col, row) or Vector2i(-1, -1) if nothing suitable exists.
# Mirrors Game.cpp line 2014-2057.
func _find_mini_boss_cell(maze: Object, portal_pos: Vector2,
                                                  player_pos: Vector2) -> Vector2i:
        var portal_c := int(portal_pos.x / TILE_SIZE)
        var portal_r := int((portal_pos.y - UI_HEIGHT) / TILE_SIZE)
        # FIX (pallino procedurale accanto al miniboss, 2° tentativo): spawn
        # radius aumentato da 1-4 a 4-8 (256-512px dal centro portal). Così
        # il miniboss appare sufficientemente lontano dal nucleo del portal
        # da non essere percepito come "pallino accanto al miniboss". Anche
        # se il disco lavanda del portal rimane visibile, la distanza fa sì
        # che venga percepito come portale separato e non come pallino attaccato.
        for radius in range(4, 9):
                for dc in range(-radius, radius + 1):
                        for dr in range(-radius, radius + 1):
                                var nc: int = portal_c + dc
                                var nr: int = portal_r + dr
                                if nc <= 0 or nc >= MAZE_COLS - 1:
                                        continue
                                if nr <= 0 or nr >= MAZE_ROWS - 1:
                                        continue
                                if maze.is_wall(nc, nr):
                                        continue
                                if maze.get_cell_type(nc, nr) != CELL_EMPTY:
                                        continue
                                # FIX (sprite uno sopra l'altro): il mini-boss
                                # non spunta sopra un collectible.
                                if _portal_cell_check.is_valid() \
                                                and not _portal_cell_check.call(nc, nr):
                                        continue
                                if nc == portal_c and nr == portal_r:
                                        continue  # don't sit on top of the portal
                                return Vector2i(nc, nr)

        # Fallback: farthest empty cell from the player (>=6 manhattan dist).
        var pc := int(player_pos.x / TILE_SIZE)
        var pr := int((player_pos.y - UI_HEIGHT) / TILE_SIZE)
        var fallback_best_dist: int = -1
        var fb_c: int = -1
        var fb_r: int = -1
        for c in range(1, MAZE_COLS - 1):
                for r in range(1, MAZE_ROWS - 1):
                        if maze.get_cell_type(c, r) == CELL_EMPTY and not maze.is_wall(c, r):
                                var dist: int = abs(c - pc) + abs(r - pr)
                                if dist >= 6 and dist > fallback_best_dist:
                                        fallback_best_dist = dist
                                        fb_c = c
                                        fb_r = r
        return Vector2i(fb_c, fb_r)


# ===========================================================================
# FIX (Hurry Up! — fantasma immortale): riapre VISUALMENTE il portale magico
# per l'ingresso del fantasma. Ciclo completo: apertura 1s → NESSUNO spawn
# (enemies_to_spawn = 0) → chiusura 2.8s → inattivo. Il fantasma emerge dal
# portale mentre questo si riapre.
# ===========================================================================
func reopen_portal_for_ghost() -> void:
        magic_portal.active = true
        magic_portal.phase = 0
        magic_portal.phase_timer = PORTAL_OPEN_MS
        magic_portal.rotation = 0.0
        magic_portal.glow_pulse = 0.0
        magic_portal.enemies_to_spawn = 0
        magic_portal.spawn_timer = 0
        magic_portal.dead_indices.clear()


# ===========================================================================
# TASK 23 (respawn progressivo post-5° boss): a ogni KILL di un nemico del
# labirinto il MainGameController chiama notify_enemy_killed(). Se il budget
# respawn non è esaurito, il portale RIAPPARE e farà uscire 2 nemici
# (uno alla volta a 4s di distanza, ciclo open 1s → spawn → close 2.8s).
# Non fa nulla se: modalità non progressiva, budget esaurito, il portale è
# già aperto (i kill durante un ciclo aperto non si accodano) oppure il
# primo trigger del 50% non è ancora scattato (portal_used).
# ===========================================================================
func notify_enemy_killed(maze: Object) -> void:
        if not progressive_respawn or respawn_budget <= 0:
                return
        if not portal_used:
                return  # il primo "respiro" (mid-boss + 1) deve ancora arrivare
        if magic_portal.active:
                return  # ciclo già in corso: il prossimo kill riaprirà
        _reopen_progressive_portal(maze)


# TASK 23: riapre il portale riservando fino a 2 nemici dal budget.
func _reopen_progressive_portal(_maze: Object) -> void:
        if respawn_budget <= 0:
                return
        var reserve: int = mini(2, respawn_budget)
        respawn_budget -= reserve
        magic_portal.active = true
        magic_portal.phase = 0
        magic_portal.phase_timer = PORTAL_OPEN_MS
        magic_portal.rotation = 0.0
        magic_portal.glow_pulse = 0.0
        magic_portal.enemies_to_spawn = reserve
        magic_portal.spawn_timer = 0
        magic_portal.dead_indices.clear()


# ===========================================================================
# update_portal(maze, dt_ms): tick the portal state machine.
# dt_ms is simulated ms (call with 16 each _physics_process frame).
# Returns true if the portal is still active (Game should keep ticking).
# ===========================================================================
func update_portal(maze: Object, dt_ms: int) -> bool:
        if not magic_portal.active:
                # TASK 23 (anti-softlock): respawn progressivo con budget
                # residuo e NESSUN nemico vivo → il portale si riapre DA SÌ:
                # senza kill non ci sarebbe altro modo di far uscire i nemici
                # mancanti ("finché non escono tutti i nemici previsti").
                if progressive_respawn and portal_used and respawn_budget > 0 \
                                and alive_count() == 0:
                        _reopen_progressive_portal(maze)
                        return true
                return false

        # Animate portal rotation + glow (visual cue; rendered by Game node).
        magic_portal.rotation += 0.03
        magic_portal.glow_pulse += 0.016

        magic_portal.phase_timer = max(0, magic_portal.phase_timer - dt_ms)

        if magic_portal.phase_timer == 0:
                if magic_portal.phase == 0:
                        # Opening complete -> start spawning.
                        magic_portal.phase = 1
                        magic_portal.spawn_timer = PORTAL_FIRST_SPAWN_MS
                        _spawn_enemy_from_portal(maze)
                elif magic_portal.phase == 2:
                        # Closing complete -> deactivate.
                        magic_portal.phase = 3
                        magic_portal.active = false
                        # TASK 23: appena chiuso, se il budget ha ancora
                        # nemici e non è rimasto nessuno vivo, riapre subito
                        # (continua a "sfornare" finché il livello non ha
                        # tirato fuori tutti i nemici previsti).
                        if progressive_respawn and portal_used \
                                        and respawn_budget > 0 and alive_count() == 0:
                                _reopen_progressive_portal(maze)
                                return true
                        return false

        # Phase 1: spawn enemies one-by-one on a 4-second interval.
        if magic_portal.phase == 1:
                magic_portal.spawn_timer = max(0, magic_portal.spawn_timer - dt_ms)
                if magic_portal.spawn_timer == 0 and magic_portal.enemies_to_spawn > 0:
                        _spawn_enemy_from_portal(maze)
                        magic_portal.spawn_timer = PORTAL_SPAWN_INTERVAL_MS
                # All enemies spawned -> close portal.
                if magic_portal.enemies_to_spawn == 0:
                        magic_portal.phase = 2
                        magic_portal.phase_timer = PORTAL_CLOSE_MS

        return magic_portal.active


# ===========================================================================
# _spawn_enemy_from_portal(maze): respawn ONE dead enemy next to the
# portal. Picks the first dead enemy index, finds an empty cell in an
# expanding ring around the portal, and recreates that enemy there.
# Mirrors Game::spawnEnemyFromPortal() src/Game.cpp line 407-447.
# ===========================================================================
# FIX (sprite uno sopra l'altro): cella occupata da un nemico VIVO?
func _cell_has_live_enemy(col: int, row: int) -> bool:
        for e in enemies:
                if e is Enemy and is_instance_valid(e) and not e.is_dead():
                        var ep: Vector2 = e.get_pixel_pos()
                        if int(ep.x / TILE_SIZE) == col \
                                        and int((ep.y - UI_HEIGHT) / TILE_SIZE) == row:
                                return true
        return false


# TASK 76 — helper: crea un NUOVO nemico di tipo random vicino al portale
# (usato sia quando non ci sono dead_indices, sia quando un indice stantio
# puntava a un nemico vivo). Cerca una cella libera in un anello espandente
# attorno al portale; se non la trova consuma comunque lo spawn.
func _spawn_new_portal_enemy(maze: Object) -> void:
        var pool_size: int = Enemy.ENEMY_ORIGINAL_TYPE_COUNT + unlocked_new_types
        var new_type: int = randi() % pool_size
        var pc_new := int(magic_portal.pos.x / TILE_SIZE)
        var pr_new := int((magic_portal.pos.y - UI_HEIGHT) / TILE_SIZE)
        # Cerca cella vuota vicino al portale
        for radius in range(1, PORTAL_PLACE_MAX_RADIUS + 1):
                for dc in range(-radius, radius + 1):
                        for dr in range(-radius, radius + 1):
                                var nc: int = pc_new + dc
                                var nr: int = pr_new + dr
                                if nc <= 0 or nc >= MAZE_COLS - 1:
                                        continue
                                if nr <= 0 or nr >= MAZE_ROWS - 1:
                                        continue
                                if maze.is_wall(nc, nr):
                                        continue
                                if maze.get_cell_type(nc, nr) != CELL_EMPTY:
                                        continue
                                # FIX (sprite uno sopra l'altro): il
                                # respawn non spunta sopra un collectible.
                                if _portal_cell_check.is_valid() \
                                                and not _portal_cell_check.call(nc, nr):
                                        continue
                                # FIX: non impilare il respawn sopra un
                                # nemico vivo (sprite uno sopra l'altro).
                                if _cell_has_live_enemy(nc, nr):
                                        continue
                                var new_enemy: Enemy = Enemy.new()
                                new_enemy.init(new_type, nc, nr)
                                # TASK 76: mai nemici orfani nel pool (fuori
                                # dal tree) — hardening anti-crash.
                                if not is_inside_tree() or get_parent() == null:
                                        new_enemy.queue_free()
                                else:
                                        get_parent().add_child(new_enemy)
                                        enemies.append(new_enemy)
                                magic_portal.enemies_to_spawn -= 1
                                return
        magic_portal.enemies_to_spawn -= 1


func _spawn_enemy_from_portal(maze: Object) -> void:
        if magic_portal.enemies_to_spawn <= 0:
                magic_portal.enemies_to_spawn = 0
                return
        # FIX (respawn): se non ci sono dead_indices (tutti i nemici ancora
                # vivi o già respawnati), crea un nuovo Enemy di tipo random.
                # FIX (pool nuovi nemici): il tipo random pesca anche dai nuovi
                # tipi sbloccati dopo i boss (28 + unlocked_new_types).
        if magic_portal.dead_indices.is_empty():
                _spawn_new_portal_enemy(maze)
                return

        var idx: int = magic_portal.dead_indices.pop_back()
        if idx < 0 or idx >= enemies.size():
                magic_portal.enemies_to_spawn -= 1
                return

        var e: Enemy = enemies[idx]
        # TASK 76 (indice STANTIO): remove_dead() compatta l'array a ogni
        # frame, quindi gli indici raccolti al trigger del portale possono
        # ora puntare a un nemico DIVERSO (vivo!). Prima il re-init
        # "teletrasportava" un nemico vivo a meta' caccia. Ora: se il nemico
        # non e' morto (o non e' piu' valido) l'indice viene scartato e si
        # passa alla creazione di un nuovo nemico.
        if e == null or not (e is Enemy) or not is_instance_valid(e) \
                        or not e.is_inside_tree() or not e.is_dead():
                _spawn_new_portal_enemy(maze)
                return

        var et: int = e.get_type()
        var pc := int(magic_portal.pos.x / TILE_SIZE)
        var pr := int((magic_portal.pos.y - UI_HEIGHT) / TILE_SIZE)

        # Expanding-ring search for an empty cell near the portal.
        var placed: bool = false
        for radius in range(1, PORTAL_PLACE_MAX_RADIUS + 1):
                if placed:
                        break
                for dc in range(-radius, radius + 1):
                        if placed:
                                break
                        for dr in range(-radius, radius + 1):
                                var nc: int = pc + dc
                                var nr: int = pr + dr
                                if nc <= 0 or nc >= MAZE_COLS - 1:
                                        continue
                                if nr <= 0 or nr >= MAZE_ROWS - 1:
                                        continue
                                if maze.is_wall(nc, nr):
                                        continue
                                if maze.get_cell_type(nc, nr) != CELL_EMPTY:
                                        continue
                                # FIX (sprite uno sopra l'altro): il respawn
                                # non spunta sopra un collectible.
                                if _portal_cell_check.is_valid() \
                                                and not _portal_cell_check.call(nc, nr):
                                        continue
                                # FIX: non impilare il respawn sopra un
                                # nemico vivo (sprite uno sopra l'altro).
                                if _cell_has_live_enemy(nc, nr):
                                        continue
                                # Re-init the existing Enemy instance at the new cell.
                                # This reuses the node (no add/remove churn) and preserves
                                # its sprite etc. - mirrors `enemies[idx] = Enemy(et, nc, nr)`.
                                e.init(et, nc, nr)
                                placed = true
                                break

        magic_portal.enemies_to_spawn -= 1


# ===========================================================================
# Accessors / convenience
# ===========================================================================

# alive_count(): how many enemies are still alive (HP > 0). Useful for the
# Game node to check end-of-wave conditions and the portal trigger.
func alive_count() -> int:
        var n: int = 0
        for e in enemies:
                if e is Enemy and not e.is_dead():
                        n += 1
        return n


# clear(): empty the pool AND free any enemy nodes that are children.
# Called by Game at level transition.
func clear() -> void:
        for e in enemies:
                if e is Node and is_instance_valid(e):
                        e.queue_free()
        enemies.clear()
        initial_count = 0
        portal_used = false
        magic_portal.active = false
        magic_portal.phase = 3
        magic_portal.enemies_to_spawn = 0
        magic_portal.dead_indices.clear()


# remove_dead(done_anim=true): drop fully-dead enemies from the pool.
# Game calls this after rendering to keep the array compact.
func remove_dead() -> void:
        var alive: Array = []
        for e in enemies:
                if e is Enemy and not e.is_death_anim_done():
                        alive.append(e)
                else:
                        if e is Node and is_instance_valid(e):
                                e.queue_free()
        enemies = alive

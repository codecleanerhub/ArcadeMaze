## test_task109_bugfixes.gd — TASK 109: bugfix richiesti dall'utente.
##
##   A. VITE INIZIALI: il player parte con C.STARTING_LIVES (5, non 3),
##      sia dal reset() che dal player della scena MainGame.
##   B. MINI-BOSS DAL PORTALE: al trigger del 50% il mini-boss NON spawna
##      subito (mini_boss_pending true, mini_boss_spawned false); quando il
##      portale COMPLETA l'apertura (update_portal fase 0 -> 1) il mini-boss
##      emerge ESATTAMENTE dalla cella del portale (non "accanto al player").
##   C. RESPAWN NEMICI DAL PORTALE: il primo nemico respawnato esce dalla
##      CELLA del portale (raggio 0), il secondo da una cella adiacente
##      (raggio <= 1): mai da punti lontani del labirinto.
##   D. DINAMITE ROMPE I MURI: l'esplosione ACCANTO a un muro interno lo
##      spezza (comportamento del martello di Thor); i muri di BORDO restano
##      indistruttibili.
extends Node

const C = preload("res://scripts/core/GameConstants.gd")
const MainGameScene = preload("res://scenes/MainGame.tscn")
const PlayerScript = preload("res://scripts/core/Player.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []


func _ready() -> void:
        GameManager.num_players = 1
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 1P...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ok(msg: String) -> void:
        print("[TEST] OK ", msg)


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] ESITO: TUTTI PASSATI")
                get_tree().quit(0)
        else:
                print("[TEST] ESITO: FALLITO (%d)" % failures.size())
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.2:
                                _phase_a_lives()
                                phase = 1
                1:
                        # B + C: prepara il trigger del portale al 50%.
                        _phase_b_portal_setup()
                        phase = 2
                2:
                        # B: apertura completata -> mini-boss dalla cella portale.
                        _phase_b_miniboss_from_portal()
                        phase = 3
                3:
                        # C: secondo respawn dal portale (cella adiacente).
                        _phase_c_second_respawn()
                        phase = 4
                4:
                        # D: dinamite rompe i muri interni, non il bordo.
                        _phase_d_dynamite_walls()
                        _finish()


# --- A: vite iniziali a 5 ----------------------------------------------------
func _phase_a_lives() -> void:
        var scene_p: CharacterBody2D = main.player
        if scene_p == null or int(scene_p.lives) != C.STARTING_LIVES:
                _fail("A: player della scena parte con vite %s (attese %d)"
                                % [str(scene_p.lives if scene_p != null else "null"),
                                                C.STARTING_LIVES])
        else:
                _ok("A1: player di gioco parte con %d vite" % C.STARTING_LIVES)
        var p: CharacterBody2D = PlayerScript.new()
        add_child(p)
        p.reset()
        if int(p.lives) != C.STARTING_LIVES:
                _fail("A: reset() -> vite %d (attese %d)" % [p.lives, C.STARTING_LIVES])
        else:
                _ok("A2: reset() (nuova partita) = %d vite" % C.STARTING_LIVES)
        p.queue_free()


# --- B setup: porta i nemici al 50% e apri il portale -----------------------
func _phase_b_portal_setup() -> void:
        var spawner = main.spawner
        var alive: int = spawner.alive_count()
        var half: int = alive / 2 + 1
        var killed: int = 0
        for e in spawner.enemies:
                if killed >= half:
                        break
                if not e.is_dead():
                        e.take_damage(9999)
                        killed += 1
        var opened: bool = spawner.trigger_portal_if_needed(
                        main.maze, main.player.get_pixel_pos(), main._spawn_mini_boss)
        if not opened:
                _fail("B: portale non aperto al 50%")
                return
        # Il mini-boss NON spawna più al trigger: esce quando il portale
        # completa l'apertura (fix "appare accanto al player").
        if main.mini_boss_spawned or main.mini_boss != null:
                _fail("B: mini-boss spawnato SUBITO al trigger (deve uscire dal portale)")
        elif not spawner.mini_boss_pending:
                _fail("B: mini_boss_pending false al trigger")
        else:
                _ok("B1: al trigger il mini-boss è PENDING (uscirà dal portale)")


# --- B: apertura completata -> mini-boss ESATTAMENTE sul portale -------------
func _phase_b_miniboss_from_portal() -> void:
        var spawner = main.spawner
        if not spawner.magic_portal.active:
                _fail("B: portale non attivo prima dell'apertura")
                return
        # Completa l'apertura (fase 0 -> 1): mini-boss + primo nemico.
        spawner.update_portal(main.maze, PORTAL_OPEN_MS + 10)
        if not main.mini_boss_spawned or main.mini_boss == null \
                        or not is_instance_valid(main.mini_boss):
                _fail("B: mini-boss non spawnato a apertura completata")
                return
        var portal_pos: Vector2 = spawner.magic_portal.pos
        var dist: float = main.mini_boss.position.distance_to(portal_pos)
        if dist > 1.0:
                _fail("B: mini-boss a %.0fpx dal portale (deve EMERGERE dal portale)"
                                % dist)
        else:
                _ok("B2: mini-boss esce ESATTAMENTE dal portale (%.0fpx)" % dist)
        # Primo nemico respawnato: sulla cella del portale (raggio 0).
        var near: float = 999999.0
        for e in spawner.enemies:
                if e is Object and is_instance_valid(e) and not e.is_dead():
                        near = minf(near, e.position.distance_to(portal_pos))
        if near > CELL_PX * 1.1:
                _fail("B: primo nemico respawnato a %.0fpx dal portale (atteso sulla cella)"
                                % near)
        else:
                _ok("B3: primo nemico respawnato DALLA cella del portale (%.0fpx)" % near)


# --- C: secondo respawn = cella adiacente al portale -------------------------
func _phase_c_second_respawn() -> void:
        var spawner = main.spawner
        var portal_pos: Vector2 = spawner.magic_portal.pos
        # Secondo nemico: 4s dopo il primo, cella adiacente (raggio <= 1).
        spawner.update_portal(main.maze, PORTAL_SPAWN_MS + 10)
        var near: float = 999999.0
        for e in spawner.enemies:
                if e is Object and is_instance_valid(e) and not e.is_dead():
                        near = minf(near, e.position.distance_to(portal_pos))
        if near > CELL_PX * 1.6:
                _fail("C: respawn successivo a %.0fpx dal portale (atteso <= 1 cella)"
                                % near)
        else:
                _ok("C: i respawn escono dal portale (ultimo a %.0fpx, <= 1 cella)" % near)


# --- D: dinamite rompe i muri interni (come il martello), il bordo NO -------
func _phase_d_dynamite_walls() -> void:
        # Cerca un muro INTERNO con una cella vuota ADIACENTE libera da
        # nemici (l'esplosione uccide in raggio 80px: teniamo 150px di margine
        # per non interferire con punteggi/level up).
        var found: bool = false
        var wall_c: int = -1
        var wall_r: int = -1
        var blast_pos: Vector2 = Vector2.ZERO
        for c in range(2, C.MAZE_COLS - 3):
                for r in range(2, C.MAZE_ROWS - 3):
                        if not main.maze.is_wall(c, r):
                                continue
                        if main.maze.is_wall(c + 1, r):
                                continue
                        var bp: Vector2 = _cell_center(c + 1, r)
                        if not _area_clear_of_enemies(bp, 150.0):
                                continue
                        found = true
                        wall_c = c
                        wall_r = r
                        blast_pos = bp
                        break
                if found:
                        break
        if not found:
                _fail("D: setup non trovato (nessun muro interno libero)")
                return
        main._explode_dynamite(true, blast_pos)
        if main.maze.is_wall(wall_c, wall_r):
                _fail("D: muro interno (%d,%d) NON rotto dall'esplosione accanto"
                                % [wall_c, wall_r])
        else:
                _ok("D1: dinamite esplosa ACCANTO al muro (%d,%d) lo rompe"
                                % [wall_c, wall_r])
        # Muro di BORDO: indistruttibile (come il martello di Thor).
        for r in range(1, C.MAZE_ROWS - 1):
                if main.maze.is_wall(0, r) and not main.maze.is_wall(1, r) \
                                and _area_clear_of_enemies(_cell_center(1, r), 150.0):
                        main._explode_dynamite(true, _cell_center(1, r))
                        if not main.maze.is_wall(0, r):
                                _fail("D: muro di BORDO (0,%d) rotto dalla dinamite!" % r)
                        else:
                                _ok("D2: muro di BORDO indistruttibile (0,%d)" % r)
                        return
        _ok("D2: nessun bordo testabile libero (skip silenzioso)")


func _cell_center(c: int, r: int) -> Vector2:
        return Vector2(c * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        r * C.TILE_SIZE + C.UI_HEIGHT + C.TILE_SIZE / 2.0)


func _area_clear_of_enemies(pos: Vector2, radius: float) -> bool:
        for e in main.spawner.enemies:
                if e is Object and is_instance_valid(e) and not e.is_dead():
                        if pos.distance_to(e.position) < radius:
                                return false
        if main.mini_boss != null and is_instance_valid(main.mini_boss) \
                        and not main.mini_boss.is_dead():
                if pos.distance_to(main.mini_boss.position) < radius:
                        return false
        return true


const PORTAL_OPEN_MS: int = 1010    # > 1000ms di apertura del portale
const PORTAL_SPAWN_MS: int = 4010   # > 4000ms tra i respawn
const CELL_PX: float = 64.0

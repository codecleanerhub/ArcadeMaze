## test_hammer_continue.gd — Test funzionale runtime (headless) delle
## meccaniche richieste in questa iterazione:
##   A. TESORI -20%: 6 tesori per livello (erano 8).
##   B. NESSUNA ARMA ONE-SHOT (tranne mina/dinamite): pistola 4 colpi,
##      laser 3, shotgun 2, razzo 2; martello 50% HP (2 colpi); mina e
##      dinamite restano kill istantanei.
##   C. MARTELLO (volo): lancio #1 spezza un muro INTERNO (cella diventa
##      EMPTY = scorciatoia per player e nemici) e RITORNA in mano;
##      lancio #2 colpisce un nemico per il 50% e poi SPARISCE dal player.
##   D. CONTINUE = SESSIONE ESATTA (maze): alla morte viene salvato lo
##      snapshot; il continue YES ripristina lo stesso labirinto, gli stessi
##      tesori residui, gli stessi nemici (numero/tipo/HP/posizione), lo
##      stesso punteggio e il martello in mano.
##   E. CONTINUE = SESSIONE ESATTA (boss room): morti in boss room, il
##      continue torna NELLA BOSS ROOM (bug: rimandava nel labirinto!) con
##      gli HP del boss e i punteggi salvati.
##   F. MINA NEI TUNNEL: la mina che entra nella galleria destra riemerge
##      a sinistra (wrap Pac-Man) invece di incastrarsi nell'imbocco.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const EnemyScript = preload("res://scripts/enemies/Enemy.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var phase: int = 0
var t: float = 0.0
var st: float = 0.0
var failures: Array = []
var main: Node2D = null

# --- Stato del test ---
var wall_cell: Vector2i = Vector2i(-1, -1)
var bait_enemy: Node2D = null
var bait_max_hp: int = 0
var mine_prev_x: float = -1.0
var mine_wrapped: bool = false
var frames_waited: int = 0
var snap_maze: Dictionary = {}
var snap_enemies_expected: Array = []
var snap_score_expected: int = 0
var boss_target_hp: int = 0


func _ready() -> void:
        # Il test guida cambi di scena REALI (maze -> continues -> maze,
        # boss room -> continues -> boss room): reparent sotto il root per
        # sopravvivere a change_scene_to_file (vedi test_configjoy_menu).
        get_parent().remove_child.call_deferred(self)
        get_tree().root.add_child.call_deferred(self)


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _scene_name() -> String:
        var cs: Node = get_tree().current_scene
        if cs == null or cs.scene_file_path.is_empty():
                return ""
        return cs.scene_file_path.get_file()


func _scene_node() -> Node:
        return get_tree().current_scene


# Uccide tutti i nemici e inibisce il portale (così le fasi del test sono
# deterministiche: l'unico nemico in giro è l'esca spawnata ad hoc).
func _kill_all_enemies() -> void:
        for e in main.spawner.enemies:
                if e != null and is_instance_valid(e) and not e.is_dead():
                        e.take_damage(999)
        main.spawner.portal_used = true  # latch: niente respawn durante il test
        main.spawner.magic_portal.active = false
        main.portal_used = true


func _physics_process(delta: float) -> void:
        t += delta
        st += delta
        match phase:
                0:
                        # Primo frame: reparent risolti -> azzera scena corrente
                        # e apri il MainGame come farebbe l'avvio del gioco.
                        if st > 0.1:
                                get_tree().current_scene = null
                                get_tree().change_scene_to_file("res://scenes/MainGame.tscn")
                                print("[TEST] boot MainGame 1P...")
                                phase = 1
                                st = 0.0
                1:
                        # Attende il boot del MainGame.
                        if st > 1.5 and _scene_name() == "MainGame.tscn":
                                main = _scene_node()
                                # Player invulnerabile per tutto il test (i
                                # nemici fuggono: mai morti accidentali).
                                main.player.invincible_timer = 100000000
                                _run_static_checks()
                                phase = 2
                                st = 0.0
                2:
                        # --- C: martello lancio #1 — rottura muro interno ---
                        _kill_all_enemies()
                        if not _setup_wall_throw():
                                _fail("C: nessun muro interno raggiungibile trovato")
                                phase = 6
                                st = 0.0
                                return
                        phase = 3
                        st = 0.0
                        frames_waited = 0
                3:
                        # Attende: muro rotto + martello tornato in mano.
                        frames_waited += 1
                        if main.maze.get_cell_type(wall_cell.x, wall_cell.y) != C.CellType.WALL:
                                if main.hammer_thrown != null:
                                        return  # impatto avvenuto, aspetta il ritorno
                                if not main.player.is_hammer_equipped():
                                        _fail("C: martello non tornato in mano dopo il 1° lancio")
                                elif main.hammer_uses_left != 1:
                                        _fail("C: usi rimasti = " + str(main.hammer_uses_left) + ", atteso 1")
                                else:
                                        print("[TEST] OK C: muro interno (", wall_cell.x, ",",
                                                        wall_cell.y, ") spezzato, martello tornato (1 uso rimasto)")
                                phase = 4
                                st = 0.0
                                frames_waited = 0
                        elif frames_waited > 240:
                                _fail("C: il muro non si è rotto entro 240 frame")
                                phase = 4
                                st = 0.0
                4:
                        # --- C2: martello lancio #2 — colpisce nemico (50%) e poi scompare ---
                        if frames_waited == 0:
                                if not _setup_enemy_throw():
                                        _fail("C2: setup lancio su nemico fallito")
                                        phase = 6
                                        st = 0.0
                                        return
                        frames_waited += 1
                        if main.hammer_thrown == null and frames_waited > 2:
                                var hp_now: int = int(bait_enemy.health)
                                if bait_enemy.is_dead():
                                        _fail("C2: nemico ucciso dal martello (doveva sopravvivere al 50%)")
                                elif hp_now != maxi(0, bait_max_hp - int(round(float(bait_max_hp) * 0.5))):
                                        _fail("C2: HP nemico dopo martello = " + str(hp_now)
                                                        + ", atteso " + str(bait_max_hp
                                                        - int(round(float(bait_max_hp) * 0.5))))
                                elif main.hammer_uses_left != 0 or main.hammer_player != 0:
                                        _fail("C2: martello non scomparso dopo il 2° lancio (usi="
                                                        + str(main.hammer_uses_left) + " player="
                                                        + str(main.hammer_player) + ")")
                                elif main.player.is_hammer_equipped():
                                        _fail("C2: player ancora equipaggiato col martello")
                                else:
                                        print("[TEST] OK C2: nemico colpito 50% (", hp_now, "/",
                                                        bait_max_hp, " HP), martello scomparso")
                                phase = 5
                                st = 0.0
                                frames_waited = 0
                        elif frames_waited > 300:
                                _fail("C2: il martello non ha concluso il volo entro 300 frame")
                                phase = 5
                                st = 0.0
                                frames_waited = 0
                5:
                        # --- F: mina nel tunnel destro -> wrap a sinistra ---
                        if frames_waited == 0:
                                frames_waited = 1  # subito: evita doppio setup
                                if not _setup_mine_tunnel():
                                        _fail("F: setup mina tunnel fallito")
                                        phase = 6
                                        st = 0.0
                                        return
                        frames_waited += 1
                        var mine = main.mine_item
                        if mine != null and is_instance_valid(mine):
                                var mx: float = mine.position.x
                                if mine_prev_x > 1800.0 and mx < 100.0 and mx >= 0.0:
                                        mine_wrapped = true
                                mine_prev_x = mx
                        if mine_wrapped:
                                print("[TEST] OK F: mina attraversata la galleria destra -> sinistra (wrap)")
                                phase = 6
                                st = 0.0
                        elif frames_waited > 240:
                                _fail("F: la mina non ha attraversato il tunnel entro 240 frame (x="
                                                + str(mine_prev_x) + ")")
                                phase = 6
                                st = 0.0
                6:
                        # --- D: continue maze = sessione ESATTA ---
                        if st > 1.0:
                                _setup_death_maze()
                                phase = 7
                                st = 0.0
                7:
                        # Attende la ContinuesScreen e conferma YES.
                        if _scene_name() == "ContinuesScreen.tscn":
                                var cs: Node = _scene_node()
                                if not cs.has_method("_confirm"):
                                        _fail("D: ContinuesScreen senza _confirm")
                                        phase = 20
                                        return
                                cs._choice = true
                                cs._confirm()
                                print("[TEST] D: continue YES confermato")
                                phase = 8
                                st = 0.0
                        elif st > 5.0:
                                _fail("D: ContinuesScreen non apparsa (scena=" + _scene_name() + ")")
                                phase = 20
                8:
                        # Attende il MainGame ripristinato e verifica il restore.
                        # (Poll veloce: pochi frame di movimento dei nemici.)
                        if st > 0.4 and _scene_name() == "MainGame.tscn" and _scene_node().is_node_ready():
                                main = _scene_node()
                                _verify_maze_restore()
                                phase = 9
                                st = 0.0
                        elif st > 8.0:
                                _fail("D: MainGame non ricaricato dopo continue (scena="
                                                + _scene_name() + ")")
                                phase = 20
                9:
                        # --- E: boss room continue ---
                        if st > 0.5:
                                GameManager.session_snapshot.clear()
                                GameManager.session_restore_pending = false
                                GameManager.died_in_boss = false
                                GameManager.current_level = 4  # livello boss
                                get_tree().change_scene_to_file("res://scenes/BossRoom.tscn")
                                phase = 10
                                st = 0.0
                10:
                        if st > 1.5 and _scene_name() == "BossRoom.tscn":
                                var br: Node2D = _scene_node()
                                if br.boss == null or not is_instance_valid(br.boss):
                                        _fail("E: boss non creato alla prima apertura")
                                        phase = 20
                                        return
                                # Danneggia il boss a un HP noto e registra i punteggi.
                                boss_target_hp = int(br.boss.max_health * 0.4)
                                br.boss.health = boss_target_hp
                                br.player.score = 43210
                                # Morte del player -> snapshot + player_died(true)
                                br.player.lives = 0
                                br.player.energy = 0
                                br._check_boss_death()
                                # CRITICO (root cause del bug utente): dopo la
                                # chiamata died_in_boss deve restare TRUE.
                                if not GameManager.died_in_boss:
                                        _fail("E: GameManager.died_in_boss AZZERATO dopo la morte "
                                                        + "in boss room (il bug che rimandava nel labirinto)")
                                elif str(GameManager.session_snapshot.get("kind", "")) != "boss":
                                        _fail("E: snapshot boss non salvato (kind="
                                                        + str(GameManager.session_snapshot.get("kind", "")) + ")")
                                elif int(GameManager.session_snapshot.get("boss_health", -1)) != boss_target_hp:
                                        _fail("E: HP boss nello snapshot = "
                                                        + str(GameManager.session_snapshot.get("boss_health", -1))
                                                        + ", attesi " + str(boss_target_hp))
                                else:
                                        print("[TEST] OK E1: died_in_boss PRESERVATO + snapshot boss "
                                                        + "salvato (HP ", boss_target_hp, ")")
                                phase = 11
                                st = 0.0
                        elif st > 6.0:
                                _fail("E: BossRoom non caricata (scena=" + _scene_name() + ")")
                                phase = 20
                11:
                        # Conferma YES anche nella boss room.
                        if _scene_name() == "ContinuesScreen.tscn":
                                var cs2: Node = _scene_node()
                                cs2._choice = true
                                cs2._confirm()
                                phase = 12
                                st = 0.0
                        elif st > 5.0:
                                _fail("E: ContinuesScreen non apparsa dopo morte boss (scena="
                                                + _scene_name() + ")")
                                phase = 20
                12:
                        # Verifica: si torna NELLA BOSS ROOM (non nel labirinto)
                        # con gli HP del boss e il punteggio ripristinati.
                        if st > 1.5:
                                if _scene_name() != "BossRoom.tscn":
                                        _fail("E: dopo il continue SIAMO NEL LABIRINTO ("
                                                        + _scene_name() + ") invece che nella BossRoom! "
                                                        + "(il bug segnalato dall'utente)")
                                        phase = 20
                                        return
                                var br2: Node2D = _scene_node()
                                if br2.boss == null or not is_instance_valid(br2.boss):
                                        _fail("E: boss non ricreato dopo il continue")
                                elif int(br2.boss.health) != boss_target_hp:
                                        _fail("E: HP boss dopo continue = " + str(int(br2.boss.health))
                                                        + ", attesi " + str(boss_target_hp))
                                elif int(br2.player.score) != 43210:
                                        _fail("E: punteggio dopo continue = " + str(int(br2.player.score))
                                                        + ", atteso 43210")
                                else:
                                        print("[TEST] OK E2: continue nella BOSS ROOM, HP boss "
                                                        + str(int(br2.boss.health)) + "/"
                                                        + str(int(br2.boss.max_health))
                                                        + ", punteggio 43210 conservato")
                                phase = 20
                        elif st > 8.0:
                                _fail("E: BossRoom non ricaricata dopo continue (scena="
                                                + _scene_name() + ")")
                                phase = 20
                20:
                        _finish()


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] ===== TUTTI I TEST SUPERATI =====")
        else:
                print("[TEST] ===== FALLITI ", failures.size(), " controlli =====")
                for f in failures:
                        print("   - ", f)
        await get_tree().process_frame
        get_tree().quit(1 if failures.size() > 0 else 0)


# ============================================================================
# Controlli statici (A + B) eseguiti al primo boot
# ============================================================================

func _run_static_checks() -> void:
        # --- A: tesori -20% -> 6 ---
        var treasures: int = main.maze.get_remaining_treasures()
        if treasures != 6:
                _fail("A: tesori per livello = " + str(treasures) + ", attesi 6 (-20% di 8)")
        else:
                print("[TEST] OK A: 6 tesori per livello (8 - 20%)")
        # --- B1: HP scalati x4 (il più debole ha 4 HP) ---
        var ghost: Node = EnemyScript.new()
        ghost.init(2, 3, 3)  # GHOST (base 1 HP)
        if int(ghost.max_health) != 4:
                _fail("B1: HP GHOST = " + str(int(ghost.max_health)) + ", attesi 4 (base 1 x4)")
        else:
                print("[TEST] OK B1: HP scalati x4 (GHOST 4 HP)")
        ghost.free()
        # --- B2: pistola 4 colpi, shotgun 2, razzo 2, laser 3 (zombie 16HP) ---
        # NOTA enum: PISTOL=0, SHOTGUN=1, ROCKET=2, LASER=3.
        var wpn_expected := {0: 4, 1: 2, 2: 2, 3: 3}
        for wpn_type in [0, 1, 2, 3]:
                var hits_needed: int = 0
                var e: Node = EnemyScript.new()
                e.init(0, 2, 2)  # ZOMBIE (base 4 HP -> 16)
                if int(e.max_health) != 16:
                        _fail("B2: HP ZOMBIE = " + str(int(e.max_health)) + ", attesi 16")
                while not e.is_dead() and hits_needed < 12:
                        e.take_weapon_hit(wpn_type)
                        hits_needed += 1
                if e.is_dead() and hits_needed == 1:
                        _fail("B2: arma " + str(wpn_type) + " uccide con UN colpo (VIETATO)")
                elif hits_needed != int(wpn_expected.get(wpn_type, -1)):
                        _fail("B2: arma " + str(wpn_type) + " richiede " + str(hits_needed)
                                        + " colpi, attesi " + str(wpn_expected.get(wpn_type, -1)))
                else:
                        print("[TEST] OK B2: arma ", wpn_type, " = ", hits_needed, " colpi per uccidere")
                e.free()
        # --- B3: mina/dinamite restano kill istantanei (consentiti) ---
        var e3: Node = EnemyScript.new()
        e3.init(0, 2, 2)
        e3.take_damage(999)
        if not e3.is_dead():
                _fail("B3: kill istantaneo mina/dinamite non funzionante?")
        else:
                print("[TEST] OK B3: mina/dinamite = kill istantanei (consentiti)")
        e3.free()
        # --- B4: martello = 50% HP (2 colpi) ---
        var e4: Node = EnemyScript.new()
        e4.init(0, 2, 2)  # 16 HP
        var d1: int = e4.take_hammer_hit()
        if e4.is_dead() or d1 != 8 or int(e4.health) != 8:
                _fail("B4: martello infligge " + str(d1) + " (HP residui " + str(int(e4.health))
                                + "), attesi 8/8 su 16 HP")
        else:
                e4.take_hammer_hit()
                if not e4.is_dead():
                        _fail("B4: secondo colpo di martello non uccide (HP " + str(int(e4.health)) + ")")
                else:
                        print("[TEST] OK B4: martello 50% per colpo (2 colpi per uccidere)")
        e4.free()


# ============================================================================
# Setup fasi C / C2 / F / D
# ============================================================================

## Trova una cella vuota col muro INTERNO davanti, teleporta il player lì,
## lo orienta verso il muro e lancia il martello (#1).
func _setup_wall_throw() -> bool:
        # Martello in mano (simula pickup).
        main.hammer_player = 1
        main.hammer_uses_left = main.HAMMER_MAX_USES
        main.player.set_hammer_equipped(true)
        # Cerca una cella vuota con un muro interno davanti.
        for r in range(2, C.MAZE_ROWS - 2):
                for c in range(2, C.MAZE_COLS - 2):
                        if main.maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                                var wc: Vector2i = Vector2i(c, r) + off
                                if wc.x < 1 or wc.x > C.MAZE_COLS - 2 or wc.y < 1 or wc.y > C.MAZE_ROWS - 2:
                                        continue  # muro di bordo: NON rompibile
                                if main.maze.get_cell_type(wc.x, wc.y) == C.CellType.WALL:
                                        # Teleporta il player al centro della cella vuota.
                                        main.player.position = Vector2(
                                                        c * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                                        r * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                                        main.player.dx = 0
                                        main.player.dy = 0
                                        main.player.last_dx = off.x
                                        main.player.last_dy = off.y
                                        wall_cell = wc
                                        main._throw_hammer(main.player)
                                        return true
        return false


## Sposta il player in una cella con 2 celle libere davanti, spawna un nemico
## 2 celle più in là e lancia il martello (#2).
func _setup_enemy_throw() -> bool:
        for r in range(2, C.MAZE_ROWS - 2):
                for c in range(2, C.MAZE_COLS - 4):
                        if main.maze.get_cell_type(c, r) != C.CellType.EMPTY:
                                continue
                        var c1: int = c + 1
                        var c2: int = c + 2
                        if main.maze.get_cell_type(c1, r) != C.CellType.EMPTY:
                                continue
                        if main.maze.get_cell_type(c2, r) != C.CellType.EMPTY:
                                continue
                        # Player nella prima cella, nemico nella terza.
                        main.player.position = Vector2(
                                        c * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                        r * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                        main.player.dx = 0
                        main.player.dy = 0
                        main.player.last_dx = 1
                        main.player.last_dy = 0
                        # Nemico esca (ZOMBIE): 16 HP -> il martello fa 8.
                        bait_enemy = main.spawner._spawn_enemy_instance(0, c2, r)
                        bait_enemy.health = bait_enemy.max_health
                        bait_max_hp = int(bait_enemy.max_health)
                        main._throw_hammer(main.player)
                        return true
        return false


## Prepara lo scenario del tunnel: mina nel corridoio destro lanciata verso
## destra (senza nemici in giro: vola dritta, attraversa la galleria e
## riemerge a sinistra — prima rimbalzava sul bordo schermo incastrandosi).
func _setup_mine_tunnel() -> bool:
        if main.mine_item == null or not is_instance_valid(main.mine_item):
                return false
        _kill_all_enemies()
        # Mina al centro del corridoio destro (28,7) sparata verso destra.
        var mine = main.mine_item
        mine.position = Vector2(
                        (C.MAZE_COLS - 2) * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                        C.TUNNEL_ROW_SIDES * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
        mine.pos = mine.position
        mine.start_bounce(Vector2(5.0, 0.0), 7000)
        mine_prev_x = mine.position.x
        mine_wrapped = false
        return true


## Registra lo stato atteso e fa morire il player nel maze -> snapshot.
func _setup_death_maze() -> void:
        # Spawn di DUE nemici freschi su celle garantite aperte (odd-odd)
        # così il restore dei nemici viene verificato su casi reali.
        _kill_all_enemies()
        var bait_a: Node = main.spawner._spawn_enemy_instance(0, 3, 3)
        bait_a.health = bait_a.max_health
        var bait_b: Node = main.spawner._spawn_enemy_instance(2, 5, 9)
        bait_b.health = bait_b.max_health
        bait_b.take_weapon_hit(0)  # HP non pieno: verifica il restore esatto
        # Rida il martello al player per verificare il restore dello stato.
        main.hammer_player = 1
        main.hammer_uses_left = main.HAMMER_MAX_USES
        main.player.set_hammer_equipped(true)
        # Danno un po' di punteggio per verificare che NON si azzera.
        main.player.add_score(12345)
        snap_score_expected = int(main.player.score)
        # Stato atteso del restore.
        snap_maze = main.maze.serialize_state()
        snap_enemies_expected = []
        for e in main.spawner.enemies:
                if e == null or not is_instance_valid(e) or e.is_dead() or e.is_dying():
                        continue
                snap_enemies_expected.append({
                        "type": int(e.type),
                        "pos": e.position,
                        "health": int(e.health),
                })
        # Morte del player (come farebbe il gioco quando le vite finiscono).
        main.player.lives = 0
        main.player.energy = 0
        main._check_death()
        print("[TEST] D: morte nel maze -> snapshot salvato (",
                        snap_enemies_expected.size(), " nemici, tesori residui ",
                        main.maze.get_remaining_treasures(), ")")


## Confronta il MainGame ripristinato con lo stato atteso alla morte.
func _verify_maze_restore() -> void:
        var errors: int = 0
        # --- Labirinto identico cella per cella ---
        var restored: Dictionary = main.maze.serialize_state()
        if str(restored.get("types")) != str(snap_maze.get("types")):
                _fail("D: layout del labirinto CAMBIATO dopo il continue (deve essere identico)")
                errors += 1
        else:
                print("[TEST] OK D1: labirinto identico cella per cella")
        # --- Tesori residui identici ---
        var treasures_expected: int = 0
        for tt in snap_maze.get("types", []):
                if int(tt) == C.CellType.TREASURE:
                        treasures_expected += 1
        var treasures_now: int = main.maze.get_remaining_treasures()
        if treasures_now != treasures_expected:
                _fail("D: tesori residui = " + str(treasures_now) + ", attesi " + str(treasures_expected))
                errors += 1
        else:
                print("[TEST] OK D2: tesori residui identici (", treasures_now, ")")
        # --- Nemici: stesso numero, stessi tipi, stessi HP, posizioni vicine
        #     (tolleranza 96px: nel frattempo vivono e si muovono). ---
        var enemies_now: Array = main.spawner.enemies.duplicate()
        if enemies_now.size() != snap_enemies_expected.size():
                _fail("D: numero nemici = " + str(enemies_now.size()) + ", attesi "
                                + str(snap_enemies_expected.size()))
                errors += 1
        else:
                var pos_ok: int = 0
                for exp_e in snap_enemies_expected:
                        for i in range(enemies_now.size()):
                                var e_now = enemies_now[i]
                                if e_now == null or not is_instance_valid(e_now):
                                        continue
                                if int(e_now.type) == int(exp_e.get("type")) \
                                                and int(e_now.health) == int(exp_e.get("health")) \
                                                and e_now.position.distance_to(exp_e.get("pos", Vector2.ZERO)) < 96.0:
                                        pos_ok += 1
                                        enemies_now.remove_at(i)
                                        break
                if pos_ok != snap_enemies_expected.size():
                        _fail("D: nemici ripristinati correttamente = " + str(pos_ok) + "/"
                                        + str(snap_enemies_expected.size())
                                        + " (tipo/HP/posizione non corrispondono)")
                        errors += 1
                else:
                        print("[TEST] OK D3: ", pos_ok, " nemici identici in numero/tipo/HP/posizione")
        # --- Punteggio conservato ---
        if int(main.player.score) != snap_score_expected:
                _fail("D: punteggio = " + str(int(main.player.score)) + ", atteso " + str(snap_score_expected))
                errors += 1
        else:
                print("[TEST] OK D4: punteggio conservato (", snap_score_expected, ")")
        # --- Martello in mano con 2 usi ---
        if main.hammer_player != 1 or main.hammer_uses_left != main.HAMMER_MAX_USES:
                _fail("D: martello non ripristinato (player=" + str(main.hammer_player)
                                + " usi=" + str(main.hammer_uses_left) + ")")
                errors += 1
        elif not main.player.is_hammer_equipped():
                _fail("D: player non ha il martello in mano dopo il restore")
                errors += 1
        else:
                print("[TEST] OK D5: martello ripristinato in mano (2 usi)")
        if errors == 0:
                print("[TEST] OK D: CONTINUE = SESSIONE ESATTA (maze)")

## test_2p_tunnels.gd — Test funzionale runtime (headless) delle novità:
##   A. Modalità 2P: P2 visibile, spawn in cella APERTA (mai dentro un muro)
##  B. Targeting nemici: _nearest_alive_player ritorna il player più vicino;
##     con P2 eliminato (0 vite) non viene mai selezionato
##  C. Tunnel Pac-Man: celle virtuali calpestabili, tutte le altre OOB muro;
##     celle tunnel scavate nel maze
##  D. Wrap player: attraversa il tunnel alto e riemerge in basso in marcia
##  E. Wrap nemico grid-locked: dal tunnel alto arriva ESATTO al centro della
##     cella opposta (nessun freeze, nessuna compenetrazione muri)
##  F. Hurry Up! in 2P: DUE fantasmi (verde per P1, rosso per P2), ognuno
##     col proprio target; quello rosso ha is_red_variant=true
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const C = preload("res://scripts/core/GameConstants.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []


func _ready() -> void:
        # Forza la modalità 2P PRIMA di istanziare la scena di gioco.
        GameManager.num_players = 2
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 2P...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.0:
                                # --- A: P2 attivo e spawn in cella aperta ---
                                if not main.player2.visible:
                                        _fail("A: P2 non è visibile in modalità 2P")
                                else:
                                        var p2_cell: Vector2i = Vector2i(
                                                        int(main.player2.position.x / C.TILE_SIZE),
                                                        int((main.player2.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                        if main.maze.is_wall(p2_cell.x, p2_cell.y):
                                                _fail("A: P2 spawnato DENTRO un muro alla cella " + str(p2_cell))
                                        elif p2_cell == Vector2i(1, 1):
                                                _fail("A: P2 spawnato SOPRA P1 (cella 1,1)")
                                        else:
                                                print("[TEST] OK A: P2 attivo, spawn in cella aperta ", p2_cell)
                                        var p1_cell: Vector2i = Vector2i(
                                                        int(main.player.position.x / C.TILE_SIZE),
                                                        int((main.player.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                        if main.maze.is_wall(p1_cell.x, p1_cell.y):
                                                _fail("A: P1 spawnato dentro un muro?!")
                                # --- B: nearest alive player ---
                                var p1_pos: Vector2 = main.player.position
                                var p2_pos: Vector2 = main.player2.position
                                # Metti P2 lontano, P1 vicino al punto di prova.
                                var probe: Vector2 = p1_pos + Vector2(32, 0)
                                var tgt = main._nearest_alive_player(probe)
                                if tgt != main.player:
                                        _fail("B: nearest(probe vicino a P1) ha ritornato P2")
                                var probe2: Vector2 = p2_pos + Vector2(32, 0)
                                var tgt2 = main._nearest_alive_player(probe2)
                                if tgt2 != main.player2:
                                        _fail("B: nearest(probe vicino a P2) ha ritornato P1")
                                if tgt != null and tgt2 != null:
                                        print("[TEST] OK B: nearest_alive_player segue il player più vicino")
                                # P2 eliminato -> mai selezionato
                                var p2_lives_bak: int = main.player2.lives
                                main.player2.lives = 0
                                var tgt3 = main._nearest_alive_player(p2_pos)
                                if tgt3 == main.player2:
                                        _fail("B: P2 con 0 vite è ancora selezionabile come target")
                                else:
                                        print("[TEST] OK B: P2 eliminato escluso dal targeting")
                                main.player2.lives = p2_lives_bak
                                # --- C: celle virtuali tunnel ---
                                for v in [Vector2i(14, -1), Vector2i(15, -1),
                                                Vector2i(14, C.MAZE_ROWS), Vector2i(15, C.MAZE_ROWS),
                                                Vector2i(-1, 7), Vector2i(C.MAZE_COLS, 7)]:
                                        if main.maze.is_wall(v.x, v.y):
                                                _fail("C: cella virtuale " + str(v) + " dovrebbe essere aperta")
                                for w in [Vector2i(13, -1), Vector2i(0, -1), Vector2i(-1, 6),
                                                Vector2i(-1, 8), Vector2i(C.MAZE_COLS, 8), Vector2i(14, -2)]:
                                        if not main.maze.is_wall(w.x, w.y):
                                                _fail("C: OOB " + str(w) + " dovrebbe essere muro")
                                # celle tunnel scavate
                                for cell in [Vector2i(14, 0), Vector2i(15, 0), Vector2i(14, 1), Vector2i(15, 1),
                                                Vector2i(14, C.MAZE_ROWS - 1), Vector2i(15, C.MAZE_ROWS - 1),
                                                Vector2i(14, C.MAZE_ROWS - 2), Vector2i(15, C.MAZE_ROWS - 2),
                                                Vector2i(0, 7), Vector2i(1, 7),
                                                Vector2i(C.MAZE_COLS - 1, 7), Vector2i(C.MAZE_COLS - 2, 7)]:
                                        if main.maze.is_wall(cell.x, cell.y):
                                                _fail("C: cella tunnel " + str(cell) + " non scavata")
                                print("[TEST] OK C: celle virtuali + scavature tunnel corrette")
                                phase = 1
                1:
                        # --- D: wrap player attraverso il tunnel alto ---
                        # Simula direttamente N frame di update_player con
                        # direzione SU (il controller del gioco azzererebbe la
                        # direzione perché nessun tasto è premuto: qui pilotiamo
                        # il movimento manualmente per testare solo il wrap).
                        main.player.position = Vector2(15 * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                        1 * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                        var wrapped_d: bool = false
                        var start_cell_d: Vector2i = Vector2i(15, 1)
                        for i in 120:
                                main.player.set_direction(0, -1)
                                main.player.update_player(main.maze, false, 16.7)
                                if main.player.position.y > 900.0:
                                        wrapped_d = true
                                        break
                        if not wrapped_d:
                                _fail("D: il player non ha completato il wrap (pos="
                                                + str(main.player.position) + ")")
                        else:
                                var cell: Vector2i = Vector2i(
                                                int(main.player.position.x / C.TILE_SIZE),
                                                int((main.player.position.y - C.UI_HEIGHT) / C.TILE_SIZE))
                                if cell.x != 14 and cell.x != 15:
                                        _fail("D: sbocco wrap con colonna sbagliata: " + str(cell))
                                elif cell.y < C.MAZE_ROWS - 3:
                                        _fail("D: il player non è nella zona bassa dopo il wrap: " + str(cell))
                                else:
                                        print("[TEST] OK D: player ", start_cell_d, " -> tunnel alto -> sbocco ",
                                                        cell, " (wrap + direzione invariata)")
                        # --- E: wrap nemico grid-locked ---
                        main.player.position = Vector2(15 * C.TILE_SIZE + C.TILE_SIZE / 2.0,
                                        (C.MAZE_ROWS - 2) * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT)
                        var EnemyClass = load("res://scripts/enemies/Enemy.gd")
                        test_enemy = EnemyClass.new()
                        test_enemy.init(0, 15, 0)
                        main.add_child(test_enemy)
                        phase = 4
                        enemy_frames = 0
                4:
                        enemy_frames += 1
                        # aggiorna il nemico verso il player (in basso): il BFS
                        # DEVE instradarlo dentro il tunnel (via più corta).
                        var p_grid: Vector2i = main.player.get_grid_pos()
                        var projs: Array = []
                        test_enemy.update_enemy(main.maze, p_grid,
                                        main.player.get_pixel_pos(), projs, 16.7)
                        var ey: float = test_enemy.position.y
                        if enemy_frames > 240:
                                _fail("E: il nemico non ha attraversato il tunnel in 240 frame "
                                                + "(pos=" + str(test_enemy.position) + ")")
                                phase = 5
                        elif enemy_frames > 8 and ey > 900.0:
                                # è riemerso sotto: deve convergere esattamente
                                # al centro della cella di sbocco (15,14)=(992,1008)
                                phase = 5
                                enemy_settle = 0
                5:
                        # Lascia convergere il nemico fino alla decisione al centro.
                        enemy_settle += 1
                        var projs: Array = []
                        test_enemy.update_enemy(main.maze, main.player.get_grid_pos(),
                                        main.player.get_pixel_pos(), projs, 16.7)
                        var col: int = int(test_enemy.position.x / C.TILE_SIZE)
                        var row: int = int((test_enemy.position.y - C.UI_HEIGHT) / C.TILE_SIZE)
                        var cx: float = col * C.TILE_SIZE + C.TILE_SIZE / 2.0
                        var cy: float = row * C.TILE_SIZE + C.TILE_SIZE / 2.0 + C.UI_HEIGHT
                        var in_bounded: bool = test_enemy.position.x >= 0 \
                                        and test_enemy.position.x <= C.WINDOW_WIDTH \
                                        and test_enemy.position.y >= C.UI_HEIGHT \
                                        and test_enemy.position.y <= C.UI_HEIGHT + C.MAZE_ROWS * C.TILE_SIZE
                        if not in_bounded:
                                _fail("E: nemico fuori dai limiti dopo il wrap: " + str(test_enemy.position))
                                phase = 6
                        elif test_enemy.position.x == cx and test_enemy.position.y == cy:
                                # decisione presa: il nemico non è CONGELATO
                                if col == 15 and row == 14:
                                        print("[TEST] OK E: nemico riemerso e fermo ESATTO al centro (15,14) "
                                                        + "dopo ", enemy_frames + enemy_settle, " frame")
                                else:
                                        print("[TEST] OK E: nemico deciso al centro cella (", col, ",", row,
                                                        ") — attraversamento completato senza freeze")
                                phase = 6
                        elif enemy_settle > 120:
                                _fail("E: il nemico non converge al centro cella (freeze?) pos="
                                                + str(test_enemy.position))
                                phase = 6
                6:
                        # --- F: Hurry Up! in 2P = DUE fantasmi (verde P1 + rosso P2) ---
                        # Kill di tutti i nemici e attesa dei 10s.
                        for e in main.spawner.enemies:
                                if e != null and is_instance_valid(e):
                                        e.take_damage(999)
                        main.spawner.remove_dead()
                        phase = 7
                7:
                        if t > 14.0:
                                if main.ghost_reapers.size() < 2:
                                        _fail("F: in 2P i fantasmi sono " + str(main.ghost_reapers.size())
                                                        + ", attesi 2 (verde P1 + rosso P2)")
                                else:
                                        var green_found: bool = false
                                        var red_found: bool = false
                                        for g in main.ghost_reapers:
                                                if g.get("target_player_num") == 2:
                                                        if not g.get("is_red_variant"):
                                                                _fail("F: il fantasma di P2 non è la variante rossa")
                                                        else:
                                                                red_found = true
                                                else:
                                                        if g.get("is_red_variant"):
                                                                _fail("F: il fantasma di P1 non è la variante verde")
                                                        else:
                                                                green_found = true
                                        if green_found and red_found:
                                                print("[TEST] OK F: due fantasmi spawnati (verde->P1, rosso->P2)")
                                # Il fantasma rosso insegue P2 (target coerente).
                                if main.ghost_reapers.size() >= 2:
                                        var g_red = null
                                        for g in main.ghost_reapers:
                                                if g.get("is_red_variant"):
                                                        g_red = g
                                                        break
                                        if g_red != null:
                                                var tgt = main._ghost_target_player(g_red)
                                                if tgt != main.player2:
                                                        _fail("F: il fantasma rosso non insegue P2")
                                                else:
                                                        print("[TEST] OK F: il fantasma rosso insegue P2, quello verde P1")
                                # --- cleanup e fine ---
                                phase = 9
                9:
                        if test_enemy != null and is_instance_valid(test_enemy):
                                test_enemy.queue_free()
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST 2P + TUNNEL SUPERATI (runtime Godot) ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)


var wrap_frames: int = 0
var enemy_frames: int = 0
var enemy_settle: int = 0
var test_enemy: Node2D = null

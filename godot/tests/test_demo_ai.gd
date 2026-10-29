## test_demo_ai.gd — TASK 76: verifica NUMERICA della nuova AI demo.
##
## L'AI precedente (segnalazione utente) "va avanti e indietro impacciandosi
## tra i nemici". Metriche obiettive su 25s di demo REALE (headless):
##   * celle uniche visitate (esplorazione: > 12 su 25s)
##   * tesori raccolti (la AI cerca i tesori quando i nemici sono lontani)
##   * INVERSIONI di direzione a raffica (dx che flip-flippa entro 300ms):
##     il sintomo "avanti e indietro" — attese < 6 in 25s
##   * distanza minima nemico-player e sopravvivenza (dato, non criterio)
extends Node

var demo: Node = null
var t: float = 0.0
var last_cell: Vector2i = Vector2i(-999, -999)
var visited: Dictionary = {}
var last_dx: int = 0
var last_dy: int = 0
var dx_change_t: float = 0.0
var reversals: int = 0
var recent_dirs: Array = []  # [(t, dx, dy)] ultimi 400ms
var treasures_start: int = -1
var sample_t: float = 0.0
var min_enemy_dist: float = 1e9


func _ready() -> void:
        process_mode = Node.PROCESS_MODE_ALWAYS
        LoadingScreen.skip_boot_hold()
        GameManager.reset_run()
        demo = load("res://scenes/DemoMode.tscn").instantiate()
        get_tree().root.add_child.call_deferred(demo)
        print("[TEST] boot DemoMode")


func _physics_process(delta: float) -> void:
        t += delta
        if demo == null or not demo.is_node_ready():
                return
        var player = demo.player
        if player == null:
                return
        if treasures_start < 0:
                treasures_start = demo.maze.get_remaining_treasures()
        sample_t += delta
        if sample_t >= 0.25:
                sample_t = 0.0
                var cell: Vector2i = player.get_grid_pos()
                if cell != last_cell:
                        visited[cell] = true
                        last_cell = cell
                # distanza dal nemico vivo piu' vicino
                for e in demo.spawner.enemies:
                        if is_instance_valid(e) and not e.is_dead():
                                var d: float = player.get_pixel_pos().distance_to(e.get_pixel_pos())
                                if d < min_enemy_dist:
                                        min_enemy_dist = d
                print("[DEMO] t=%.1f cell=%s moving=(%d,%d) tesori_raccolti=%d" % [
                                t, str(cell), player.dx, player.dy,
                                treasures_start - demo.maze.get_remaining_treasures()])
        # conteggio inversioni: cambio direzione con segno OPPOSTO entro 400ms
        if player.dx != last_dx or player.dy != last_dy:
                if (player.dx != 0 or player.dy != 0) and (last_dx != 0 or last_dy != 0):
                        recent_dirs.append([t, player.dx, player.dy])
                        # elimina sample piu' vecchi di 400ms
                        while recent_dirs.size() > 0 and t - recent_dirs[0][0] > 0.4:
                                recent_dirs.pop_front()
                        # inversione = direzione opposta alla precedente entro la finestra
                        if recent_dirs.size() >= 2:
                                var prev: Array = recent_dirs[recent_dirs.size() - 2]
                                if t - prev[0] <= 0.4 \
                                                and prev[1] == -player.dx and prev[2] == -player.dy \
                                                and (player.dx != 0 or player.dy != 0):
                                        reversals += 1
                last_dx = player.dx
                last_dy = player.dy
        if t >= 25.0:
                _report()


func _report() -> void:
        var treasures: int = treasures_start - demo.maze.get_remaining_treasures()
        print("[REPORT] celle_visitate=%d tesori_raccolti=%d inversioni_400ms=%d dist_min_nemico=%.0fpx" % [
                        visited.size(), treasures, reversals, min_enemy_dist])
        var ok: bool = true
        if visited.size() < 12:
                print("[TEST FAIL] esplorazione insufficiente: %d celle (min 12)" % visited.size())
                ok = false
        if reversals > 6:
                print("[TEST FAIL] troppe inversioni a raffica: %d (max 6) — AI ancora 'avanti e indietro'" % reversals)
                ok = false
        if ok:
                print("[TEST PASS] AI demo: esplorazione e stabilita' direzione OK")
        get_tree().quit(0 if ok else 1)

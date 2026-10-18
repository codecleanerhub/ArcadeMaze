## test_progressive_respawn.gd — TASK 23: respawn PROGRESSIVO del portale
## dopo il 5° boss (dal livello 21). Verifica nel runtime REALE (headless):
##
##   A. Al livello 21: flag progressivo attivo, budget = nemici del livello
##      (11 = 6 base + 5 boss sconfitti); al livello 17 NON progressivo.
##   B. Primo trigger (soglia 50%): il portale fa uscire SOLO 1 nemico
##      (+ mini-boss via callback), budget 11 -> 10.
##   C. Ciclo portale completato (open -> spawn -> close): porta chiusa.
##      Una KILL (notify_enemy_killed) riapre il portale con 2 nemici
##      riservati (budget 10 -> 8).
##   D. Anti-softlock: budget residuo + NESSUN nemico vivo -> update_portal
##      riapre il portale da solo.
##   E. Budget esaurito (0): notify non riapre nulla; respawn_pending false.
##   F. HURRY UP non scatta finché il budget respawn non è esaurito.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var noop_mb: Callable = Callable()


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


func _physics_process(delta: float) -> void:
        t += delta
        if main == null or not main.is_node_ready():
                return
        match phase:
                0:
                        if t > 1.0:
                                noop_mb = func(_c, _r) -> void: pass
                                # Livello 17: NON progressivo (controllo).
                                main.start_level(17)
                                if main.spawner.progressive_respawn:
                                        _fail("A: livello 17 marcato progressivo?!")
                                else:
                                        _ok("A1: livello 17 NON progressivo (pre-5° boss)")
                                # Livello 21: progressivo, budget = wave size.
                                main.start_level(21)
                                var expected: int = main.spawner.enemies.size()
                                if not main.spawner.progressive_respawn:
                                        _fail("A: livello 21 NON progressivo")
                                elif main.spawner.respawn_budget != expected:
                                        _fail("A: budget " + str(main.spawner.respawn_budget)
                                                        + " != nemici " + str(expected))
                                elif not main.spawner.respawn_pending():
                                        _fail("A: respawn_pending false con budget > 0")
                                else:
                                        _ok("A2: livello 21 progressivo, budget = " + str(expected))
                                phase = 1
                1:
                        # B: porta sotto il 50% e trigger.
                        var alive: int = main.spawner.alive_count()
                        var half: int = alive / 2 + 1
                        var killed: int = 0
                        for e in main.spawner.enemies:
                                if killed >= half:
                                        break
                                if not e.is_dead():
                                        e.take_damage(9999)
                                        killed += 1
                        var p_pos: Vector2 = main.player.get_pixel_pos()
                        var opened: bool = main.spawner.trigger_portal_if_needed(
                                        main.maze, p_pos, noop_mb)
                        if not opened:
                                _fail("B: portale non aperto al 50%")
                        elif int(main.spawner.magic_portal.enemies_to_spawn) != 1:
                                _fail("B: primo respawn con " \
                                                + str(main.spawner.magic_portal.enemies_to_spawn)
                                                + " nemici (atteso 1)")
                        elif main.spawner.respawn_budget != 10:
                                _fail("B: budget dopo primo trigger = " \
                                                + str(main.spawner.respawn_budget) + " (atteso 10)")
                        else:
                                _ok("B: primo respawn = 1 nemico (+miniboss), budget 11 -> 10")
                        phase = 2
                2:
                        # C: completa il ciclo del portale (open 1s + spawn 0.5s
                        # + close 2.8s) poi una KILL riapre con 2.
                        for i in 8:
                                main.spawner.update_portal(main.maze, 1000)
                        if main.spawner.magic_portal.active:
                                _fail("C: il portale non si è chiuso dopo il ciclo")
                                phase = 9
                                return
                        # porta il budget a 10 confermato, simula UNA kill
                        main.spawner.notify_enemy_killed(main.maze)
                        if not main.spawner.magic_portal.active:
                                _fail("C: il portale NON si è riaperto dopo una kill")
                        elif int(main.spawner.magic_portal.enemies_to_spawn) != 2:
                                _fail("C: kill riapre con " \
                                                + str(main.spawner.magic_portal.enemies_to_spawn)
                                                + " nemici (attesi 2)")
                        elif main.spawner.respawn_budget != 8:
                                _fail("C: budget dopo kill = " \
                                                + str(main.spawner.respawn_budget) + " (atteso 8)")
                        else:
                                _ok("C: ogni kill riapre il portale con 2 nemici (budget 10 -> 8)")
                        phase = 3
                3:
                        # D: anti-softlock — chiudi il portale, uccidi TUTTI,
                        # il portale si riapre da solo finché c'è budget.
                        for i in 8:
                                main.spawner.update_portal(main.maze, 1000)
                        for e in main.spawner.enemies:
                                if not e.is_dead():
                                        e.take_damage(9999)
                        if main.spawner.alive_count() != 0:
                                _fail("D: setup — nemici non tutti morti")
                                phase = 9
                                return
                        main.spawner.update_portal(main.maze, 16)
                        if not main.spawner.magic_portal.active:
                                _fail("D: anti-softlock — il portale NON si riapre da solo")
                        elif int(main.spawner.magic_portal.enemies_to_spawn) != 2:
                                _fail("D: anti-softlock ha riservato " \
                                                + str(main.spawner.magic_portal.enemies_to_spawn))
                        else:
                                _ok("D: budget + zero nemici -> riapertura automatica (2 riservati)")
                        phase = 4
                4:
                        # E: budget esaurito -> notify non fa nulla.
                        main.spawner.respawn_budget = 0
                        var was_active: bool = main.spawner.magic_portal.active
                        main.spawner.magic_portal.active = false
                        main.spawner.magic_portal.enemies_to_spawn = 0
                        main.spawner.notify_enemy_killed(main.maze)
                        if main.spawner.magic_portal.active:
                                _fail("E: notify ha riaperto il portale con budget 0")
                        elif main.spawner.respawn_pending():
                                _fail("E: respawn_pending true con budget 0")
                        else:
                                _ok("E: budget esaurito -> nessun respawn, coda chiusa")
                        was_active = false
                        phase = 5
                5:
                        # F: HURRY UP non scatta con budget residuo; scatta con 0
                        # (forza il timer tesori oltre i 10s).
                        main.spawner.respawn_budget = 5
                        main._since_last_treasure_ms = 99999.0
                        main.hurry_up_active = false
                        main._trigger_hurry_up(Vector2.ZERO)
                        # (con budget: il check _update_hurry_up NON deve sparare
                        # i fantasmi — si verifica via la guardia all_dead.)
                        main.spawner.respawn_budget = 0
                        main.hurry_up_active = false
                        var portal_active: bool = main.spawner.magic_portal.active
                        main._update_hurry_up(16.0, main.player.get_grid_pos(),
                                        main.player.get_pixel_pos())
                        if not main.hurry_up_active and not portal_active:
                                _fail("F: hurry up NON scattato con budget 0 e timer scaduto")
                        elif main.hurry_up_active:
                                _ok("F: hurry up solo a budget esaurito (guardia attiva)")
                        else:
                                # il portale era attivo: la guardia ha fatto bene a non sparare
                                _ok("F: guardia hurry up con portale attivo (nessun fantasma)")
                        phase = 9
                9:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST RESPAWN PROGRESSIVO SUPERATI ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)

## test_task84_frozen_respawn.gd — TASK 84: bug "quadrati bianchi sul portale".
##
## Root cause: freeze_kill() lascia il nemico come statua di ghiaccio (dead
## ma non rimovibile, TASK 50); al trigger del portale le statue finivano in
## dead_indices e venivano respawn-ate via init() SENZA reset di 'frozen' →
## nemici VIVI ma congelati per sempre vicino al portale (mostro + iceblock
## = quadrato bianco con palla celeste che nasconde il portale).
##
## Verifica (runtime REALE headless, livello 1 con 6 nemici):
##   A. freeze_kill(): health=0, frozen=true, is_dead()=true, non anim-done.
##   B. init() RESETTA frozen=false (fix Enemy.gd).
##   C. dead_indices ESCLUDE le statue congelate (fix EnemySpawner.gd).
##   D. Integrazione: congela 2 + uccidi 2 → portale → dopo il ciclo spawn
##      NESSUN nemico vivo ha frozen=true; le 2 statue RESTANO congelate
##      alle celle originali (contratto TASK 50: statua fino a fine livello).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const EnemyClass = preload("res://scripts/enemies/Enemy.gd")

var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []
var statue_cells: Array = []


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
                                _unit_tests()
                                phase = 1
                1:
                        phase = 2  # anti re-entry: marca PRIMA delle await
                        main.start_level(1)
                        await get_tree().physics_frame
                        await get_tree().physics_frame
                        _integration_setup()
                        phase = 2
                2:
                        # attende il trigger del portale (soglia 50%)
                        if main.spawner.magic_portal.active:
                                var di: Array = main.spawner.magic_portal.dead_indices
                                var statue_in_di: int = 0
                                for i in di:
                                        var e = main.spawner.enemies[i]
                                        if e is EnemyClass and e.is_frozen():
                                                statue_in_di += 1
                                if statue_in_di == 0:
                                        _ok("C: dead_indices esclude le statue congelate (%d indici)" % di.size())
                                else:
                                        _fail("C: %d statue congelate presenti in dead_indices" % statue_in_di)
                                phase = 3
                        elif t > 20.0:
                                _fail("timeout: portale mai attivato")
                                _finish()
                3:
                        # aspetta la fase di spawn (open 1s + spawn ogni ~4s)
                        if t > 20.0 or main.spawner.magic_portal.phase >= 2:
                                _integration_verify()
                                _finish()


func _unit_tests() -> void:
        # A: freeze_kill() → statua
        var e: Node = EnemyClass.new()
        add_child(e)
        e.init(0, 2, 2)
        e.freeze_kill()
        if e.is_dead() and e.is_frozen() and not e.is_death_anim_done():
                _ok("A: freeze_kill() → statua (dead+frozen, non rimovibile)")
        else:
                _fail("A: freeze_kill() stato inatteso (dead=%s frozen=%s)" % [
                        e.is_dead(), e.is_frozen()])
        # B: init() resetta frozen
        e.init(0, 3, 3)
        if not e.is_frozen() and not e.is_dead():
                _ok("B: init() resetta frozen=false e riporta in vita")
        else:
                _fail("B: init() NON resetta frozen (frozen=%s dead=%s)" % [
                        e.is_frozen(), e.is_dead()])
        e.queue_free()


func _integration_setup() -> void:
        var spawner: Node = main.spawner
        var frozen_n: int = 0
        var killed: int = 0
        statue_cells.clear()
        for e in spawner.enemies:
                if e is EnemyClass and not e.is_dead():
                        if frozen_n < 2:
                                e.freeze_kill()
                                frozen_n += 1
                                statue_cells.append(e.position)
                        elif killed < 2:
                                e.health = 0
                                killed += 1
        print("[TEST] setup: 2 statue + 2 morti → vivi=%d / %d" % [
                spawner.alive_count(), spawner.enemies.size()])


func _integration_verify() -> void:
        var live_frozen: int = 0
        var statues_ok: int = 0
        var statue_gone: int = 0
        for e in main.spawner.enemies:
                if e is EnemyClass and not e.is_dead():
                        if e.is_frozen():
                                live_frozen += 1
                elif e is EnemyClass and e.is_frozen():
                        # statua: deve essere ancora alla cella originale
                        var idx: int = 0
                        var nearest: float = 99999.0
                        for sc in statue_cells:
                                var d: float = e.position.distance_to(sc)
                                if d < nearest:
                                        nearest = d
                        if nearest < 1.0:
                                statues_ok += 1
                        else:
                                statue_gone += 1
                                print("[TEST] statua spostata: %s (dist %.1f da origine più vicina)" % [
                                        e.position, nearest])
        if live_frozen == 0:
                _ok("D1: nessun nemico VIVO congelato dopo il respawn del portale")
        else:
                _fail("D1: %d nemici VIVI ancora congelati (il bug!)" % live_frozen)
        if statue_gone == 0 and statues_ok == 2:
                _ok("D2: le 2 statue congelate RESTANO al loro posto (contratto TASK 50)")
        else:
                _fail("D2: statue %d al posto / %d spostate (attese 2/0)" % [statues_ok, statue_gone])


func _finish() -> void:
        if failures.is_empty():
                print("[TEST] ==== TEST TASK84 FROZEN RESPAWN SUPERATO ====")
                get_tree().quit(0)
        else:
                print("[TEST] ==== TEST TASK84 FALLITO (%d) ====" % failures.size())
                get_tree().quit(1)

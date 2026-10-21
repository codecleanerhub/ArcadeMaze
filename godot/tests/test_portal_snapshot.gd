## test_portal_snapshot.gd — TASK 40 (regressione bug utente): crash
## "Invalid access to property or key 'phase_timer_ms' on a base object of
## type 'Dictionary'" in _build_session_snapshot alla MORTE con PORTALE
## ATTIVO (fantasmi immortali dell'HurryUp nel log).
##
## ROOT CAUSE: lo snapshot leggeva chiavi INESISTENTI del dict magic_portal
## dello spawner (quelle vere sono "phase_timer" e "spawn_timer", senza
## suffisso _ms). Conseguenze: SCRIPT ERROR alla morte (session_snapshot
## persa -> continue senza sessione esatta) e, sul lato restore, scrittura
## di chiavi fantasma "*_ms" mai lette dalla state machine del portale.
##
##   A. SNAPSHOT SENZA CRASH con portale attivo (il caso esatto del log).
##   B. I valori del portale finiscono nello snapshot (phase_timer_ms /
##      spawn_timer_ms derivati dalle chiavi reali phase_timer / spawn_timer).
##   C. CONTINUE REALE (session_restore_pending + start_level): il portale
##      riprende con le chiavi VERE valorizzate e senza chiavi fantasma.
##   D. update_portal gira senza errori dopo il restore (state machine ok).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")

var main: Node2D = null
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
                print("[TEST] test_portal_snapshot: TUTTO VERDE")
                get_tree().quit(0)
        else:
                print("[TEST] test_portal_snapshot: ", failures.size(), " FALLI")
                get_tree().quit(1)


func _physics_process(delta: float) -> void:
        t += delta
        if t > 60.0:
                _fail("timeout globale del test (60s)")
                get_tree().quit(1)
                return
        if main == null or not main.is_node_ready():
                return
        if t > 1.0:
                _run_all()
                _finish()


func _run_all() -> void:
        main.start_level(10)
        var sp: Node = main.spawner

        # --- A. snapshot con portale ATTIVO (crash del log utente) --------
        # Stato identico a un HurryUp in corso: fase spawning con coda.
        sp.magic_portal.active = true
        sp.magic_portal.phase = 1
        sp.magic_portal.phase_timer = 1234
        sp.magic_portal.spawn_timer = 567
        sp.magic_portal.enemies_to_spawn = 2
        sp.magic_portal.pos = Vector2(500.0, 600.0)
        var snap: Dictionary = {}
        snap = main._build_session_snapshot()
        if snap.is_empty():
                _fail("A: snapshot vuoto (funzione interrotta dall'errore?)")
                return
        var portal_snap: Dictionary = snap.get("portal", {})
        if portal_snap.is_empty() or not bool(portal_snap.get("active", false)):
                _fail("A: portale attivo non finito nello snapshot")
        else:
                _ok("A: snapshot con portale attivo SENZA errori di script "
                                + "(il crash del log utente e' risolto)")

        # --- B. valori portati nello snapshot ------------------------------
        if int(portal_snap.get("phase_timer_ms", -1)) != 1234:
                _fail("B: phase_timer_ms nello snapshot = %d, atteso 1234"
                                % int(portal_snap.get("phase_timer_ms", -1)))
        elif int(portal_snap.get("spawn_timer_ms", -1)) != 567:
                _fail("B: spawn_timer_ms nello snapshot = %d, atteso 567"
                                % int(portal_snap.get("spawn_timer_ms", -1)))
        elif int(portal_snap.get("phase", -1)) != 1:
                _fail("B: phase nello snapshot = %d, attesa 1"
                                % int(portal_snap.get("phase", -1)))
        else:
                _ok("B: timer/phase portati correttamente nello snapshot")

        # --- C. continue reale: start_level con session_restore_pending ----
        GameManager.session_snapshot = snap
        GameManager.session_restore_pending = true
        main.start_level(10)
        if not sp.magic_portal.active:
                _fail("C: portale non riattivato dal restore")
        elif int(sp.magic_portal.phase_timer) != 1234:
                _fail("C: chiave REALE phase_timer = %d, atteso 1234 "
                                + "(restore scrive chiavi fantasma?)"
                                % int(sp.magic_portal.phase_timer))
        elif int(sp.magic_portal.spawn_timer) != 567:
                _fail("C: chiave REALE spawn_timer = %d, atteso 567"
                                % int(sp.magic_portal.spawn_timer))
        elif sp.magic_portal.has("phase_timer_ms") \
                        or sp.magic_portal.has("spawn_timer_ms"):
                _fail("C: chiavi fantasma *_ms presenti dopo il restore")
        else:
                _ok("C: continue = portale ripristinato sulle chiavi reali "
                                + "(phase_timer=1234, spawn_timer=567)")

        # --- D. la state machine gira dopo il restore -----------------------
        for i in 30:  # ~0.5s simulati
                sp.update_portal(main.maze, 16)
        if not sp.magic_portal.active and sp.magic_portal.enemies_to_spawn > 0:
                _fail("D: portale chiuso con coda residua inattesa")
        elif int(sp.magic_portal.phase) != 1 and sp.magic_portal.enemies_to_spawn > 0:
                _fail("D: fase incoerente dopo update (%d)"
                                % int(sp.magic_portal.phase))
        else:
                _ok("D: update_portal post-restore senza errori "
                                + "(timer decrementati: %d/%d)"
                                % [int(sp.magic_portal.phase_timer),
                                   int(sp.magic_portal.spawn_timer)])

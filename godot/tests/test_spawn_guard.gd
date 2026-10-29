## test_spawn_guard.gd — TASK 38: immortalita' + LAMPEGGIO di 3 secondi
## alla NASCITA e alla RINASCITA del player (dopo una morte), per dare
## il tempo di allontanarsi dai nemici.
##
##   A. COSTANTI: SPAWN_GUARD_MS = 3000, lampeggio 250ms (~4 Hz).
##   B. NASCITA: start_level(10) arma la guardia (3000ms) -> il player e'
##      invulnerabile e take_damage / take_hazard_damage NON fanno nulla
##      (energia e vite invariate) finche' la guardia vive.
##   C. LAMPEGGIO: campionando modulate.a su ~1.2s di update_player si
##      vedono sia fotogrammi PIENI (alpha ~1) sia fotogrammi QUASI
##      TRASPARENTI (alpha < 0.5): il corpo pulsa ma non sparisce mai.
##   D. SCADENZA: dopo ~3s simulati la guardia finisce -> il player torna
##      vulnerabile (take_damage ora toglie energia) e il modulate torna
##      pieno (alpha 1).
##   E. RINASCITA: morte simulata (energia 1 + colpo fatale a guardia
##      esaurita) -> vita persa, respawn e guardia RIARMATA a 3000ms.
extends Node

const PlayerScript = preload("res://scripts/core/Player.gd")
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
                print("[TEST] test_spawn_guard: TUTTO VERDE")
                get_tree().quit(0)
        else:
                print("[TEST] test_spawn_guard: ", failures.size(), " FALLI")
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
        var p: CharacterBody2D = main.player

        # --- A. costanti ---------------------------------------------------
        if PlayerScript.SPAWN_GUARD_MS != 3000:
                _fail("A: SPAWN_GUARD_MS %d, atteso 3000"
                                % PlayerScript.SPAWN_GUARD_MS)
        elif absf(PlayerScript.SPAWN_GUARD_BLINK_MS - 250.0) > 0.5:
                _fail("A: SPAWN_GUARD_BLINK_MS %.0f, attesa 250"
                                % PlayerScript.SPAWN_GUARD_BLINK_MS)
        else:
                _ok("A: guardia 3000ms, lampeggio 250ms (~4 Hz)")

        # --- B. nascita a inizio livello + immortalita' --------------------
        main.start_level(10)
        if p.spawn_guard_ms != 3000:
                _fail("B: start_level non arma la guardia (%d)"
                                % p.spawn_guard_ms)
        elif not p.is_invulnerable():
                _fail("B: player non invulnerabile alla nascita")
        else:
                var e0: int = p.energy
                var l0: int = p.lives
                p.take_damage()
                p.take_damage()
                p.take_hazard_damage(3)
                if p.energy != e0 or p.lives != l0:
                        _fail("B: danno subito durante la guardia "
                                        + "(energia %d->%d, vite %d->%d)"
                                        % [e0, p.energy, l0, p.lives])
                else:
                        _ok("B: nascita = guardia 3s attiva, danni nemici "
                                        + "e hazard ignorati")

        # --- C. lampeggio del corpo ----------------------------------------
        var saw_full: bool = false
        var saw_blink: bool = false
        for _i in 75:  # ~1.2s simulati
                p.update_player(main.maze, false, 16.0)
                if p.modulate.a > 0.9:
                        saw_full = true
                elif p.modulate.a < 0.5:
                        saw_blink = true
        if not saw_full:
                _fail("C: mai pienamente visibile durante la guardia")
        elif not saw_blink:
                _fail("C: mai in fase trasparente durante la guardia "
                                + "(non lampeggia)")
        else:
                _ok("C: il player LAMPEGGIA durante la guardia "
                                + "(visibile / quasi trasparente)")

        # --- D. scadenza della guardia --------------------------------------
        for _i in 200:  # ~3.2s simulati in piu': la guardia finisce
                p.update_player(main.maze, false, 16.0)
        if p.spawn_guard_ms != 0:
                _fail("D: guardia non scaduta dopo 3s+ (%d)"
                                % p.spawn_guard_ms)
        elif p.is_invulnerable():
                _fail("D: player ancora invulnerabile a guardia esaurita")
        elif absf(p.modulate.a - 1.0) > 0.01:
                _fail("D: modulate non ripristinato a fine guardia (%.2f)"
                                % p.modulate.a)
        else:
                var e1: int = p.energy
                p.damage_timer = 0  # nessuna invulnerabilita' residua
                p.take_damage()
                if p.energy != e1 - 1:
                        _fail("D: take_damage a guardia finita non toglie "
                                        + "energia (%d->%d)" % [e1, p.energy])
                else:
                        _ok("D: guardia scaduta: vulnerabile, modulate "
                                        + "pieno, danno normale")

        # --- E. rinascita dopo una morte ------------------------------------
        p.energy = 1
        p.damage_timer = 0
        var lives_before: int = p.lives
        p.take_damage()  # colpo fatale -> collasso (TASK 87)
        # TASK 87: il respawn e' differito alla fine dell'animazione di
        # collasso (~1.2s in gioco): lo completiamo subito come fa il
        # controller a fine animazione.
        p.respawn_after_soul()
        if p.lives != lives_before - 1:
                _fail("E: morte non avvenuta (vite %d)" % p.lives)
        elif p.spawn_guard_ms != 3000:
                _fail("E: respawn non riarma la guardia (%d)"
                                % p.spawn_guard_ms)
        elif not p.is_invulnerable():
                _fail("E: player non invulnerabile dopo il respawn")
        else:
                _ok("E: rinascita post-morte: guardia riarmata (3s), "
                                + "player di nuovo immortale")

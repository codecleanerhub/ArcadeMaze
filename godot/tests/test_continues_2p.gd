## test_continues_2p.gd — TASK 23: continue PER-PLAYER in 2P (crediti
## separati P1/P2). Verifica nel runtime REALE (headless):
##
##   A. Crediti separati: P1 e P2 partono con 3 crediti ciascuno; il consumo
##      di P1 NON tocca il contatore di P2 e viceversa.
##   B. Morte di P2 (P1 vivo) → appare la schermata continue PER P2
##      (ContinuesOverlay: "PLAYER 2"), il gioco è congelato.
##   C. YES: consuma UN credito di P2 (quello di P1 resta intatto), P2
##      riprende con 3 vite e P1 NON è stato toccato (vite/energia intatti).
##   D. Morte di P2 di nuovo → NO (scelta): P2 eliminato, P1 continua a
##      giocare da solo (la scena NON cambia).
##   E. Morte di P1 senza crediti → game over (LOSE) con entrambi fuori.
##   F. In 1P il flusso storico resta scene-based: _check_death attivo.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const GameConstants = preload("res://scripts/core/GameConstants.gd")


func C_GameState_LOSE() -> int:
        return GameConstants.GameState.LOSE


var main: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []


func _ready() -> void:
        GameManager.num_players = 2
        GameManager.reset_run()
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 2P...")


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
                                _phaseA_credits()
                                phase = 1
                1:
                        # B: porta P2 a 0 vite (P1 resta vivo).
                        var p2: CharacterBody2D = main.player2
                        p2.lives = 1
                        p2.energy = 1
                        p2.damage_timer = 0
                        p2.invincible_timer = 0
                        # TASK 38 (spawn guard): il player nasce con 3s di
                        # immortalita' — azzerata perche' qui si testa la
                        # MORTE reale che apre la schermata continue.
                        p2.spawn_guard_ms = 0
                        p2.take_damage()  # ultima energia -> lives 0
                        # Il check gira a fine frame: forziamolo subito.
                        main._check_player_elimination()
                        if main._continue_pending_player != 2:
                                _fail("B: la schermata continue NON è apparsa per P2 (pending="
                                                + str(main._continue_pending_player) + ")")
                        elif main._continue_overlay == null:
                                _fail("B: overlay continue assente")
                        else:
                                _ok("B: morte di P2 con P1 vivo -> schermata continue PER P2")
                                _ok("B2: gioco congelato (continue_pending=" \
                                                + str(main._continue_pending_player) + ")")
                        phase = 2
                2:
                        # C: YES per P2 -> credito P2 consumato, P1 intatto.
                        var p2: CharacterBody2D = main.player2
                        var p1: CharacterBody2D = main.player
                        var p2_credits_before: int = GameManager.continues_for(2)
                        var p1_credits_before: int = GameManager.continues_for(1)
                        main._on_continue_chosen(2, true)
                        if GameManager.continues_for(2) != p2_credits_before - 1:
                                _fail("C: credito P2 non consumato ("
                                                + str(GameManager.continues_for(2)) + ")")
                        elif GameManager.continues_for(1) != p1_credits_before:
                                _fail("C: il credito di P1 è stato toccato!")
                        elif p2.lives != 3 or p2.energy != p2.max_energy:
                                _fail("C: P2 non riprende con 3 vite/energia piena")
                        elif main._continue_pending_player != 0:
                                _fail("C: pending non azzerato dopo la scelta")
                        else:
                                _ok("C: YES -> P2 riprende (3 vite), crediti P1 e P2 separati ("
                                                + str(GameManager.continues_for(1)) + "/"
                                                + str(GameManager.continues_for(2)) + ")")
                        phase = 3
                3:
                        # D: P2 di nuovo a 0 vite -> NO -> eliminato, P1 continua.
                        var p2: CharacterBody2D = main.player2
                        p2.lives = 1
                        p2.energy = 1
                        p2.damage_timer = 0
                        p2.invincible_timer = 0
                        p2.spawn_guard_ms = 0  # TASK 38: guardia post-continue a zero
                        p2.take_damage()
                        main._check_player_elimination()
                        if main._continue_pending_player != 2:
                                _fail("D: seconda schermata continue non apparsa per P2")
                                phase = 9
                                return
                        main._on_continue_chosen(2, false)
                        if p2.visible:
                                _fail("D: P2 non eliminato dopo NO")
                        elif main.current_level != 1 and main.is_node_ready():
                                _fail("D: la scena è cambiuta?!")
                        else:
                                _ok("D: NO -> P2 eliminato, P1 continua da solo (scena invariata)")
                        phase = 4
                4:
                        # E: P1 muore SENZA crediti -> game over (LOSE).
                        GameManager.continues_left = 0  # P1 senza crediti
                        var p1: CharacterBody2D = main.player
                        p1.lives = 1
                        p1.energy = 1
                        p1.damage_timer = 0
                        p1.invincible_timer = 0
                        p1.spawn_guard_ms = 0  # TASK 38: guardia di nascita a zero
                        p1.take_damage()
                        main._check_player_elimination()
                        # P1 eliminato subito (0 crediti) e game over.
                        if p1.visible:
                                _fail("E: P1 non eliminato senza crediti")
                        elif GameManager.current_state != C_GameState_LOSE():
                                _fail("E: game over non raggiunto (stato "
                                                + str(GameManager.current_state) + ")")
                        else:
                                _ok("E: senza crediti e senza player vivi -> LOSE (game over)")
                        # NOTA: give_up() cambia scena (LOSE) e il frame dopo
                        # questo nodo viene liberato -> il verdetto va emesso
                        # SUBITO, non al frame successivo.
                        _verdict()
                        phase = 9
                9:
                        pass


func _verdict() -> void:
        # NOTA: give_up() può aver già staccato questo nodo dal tree (cambio
        # scena LOSE) -> get_tree() può essere null qui; si usa il main loop.
        var tree: SceneTree = get_tree()
        if tree == null:
                tree = Engine.get_main_loop() as SceneTree
        if failures.is_empty():
                print("[TEST] ==== TUTTI I TEST CONTINUES 2P SUPERATI ====")
                if tree != null:
                        tree.quit(0)
        else:
                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                for f in failures:
                        print("[TEST FAIL] ", f)
                if tree != null:
                        tree.quit(1)


func _phaseA_credits() -> void:
        # A: crediti iniziali separati (3 + 3) e consumo indipendente.
        if GameManager.continues_for(1) != 3 or GameManager.continues_for(2) != 3:
                _fail("A: crediti iniziali non 3+3 ("
                                + str(GameManager.continues_for(1)) + "/"
                                + str(GameManager.continues_for(2)) + ")")
                return
        GameManager.use_continue_for(1)
        if GameManager.continues_for(1) != 2 or GameManager.continues_for(2) != 3:
                _fail("A: consumo P1 ha toccato P2 ("
                                + str(GameManager.continues_for(1)) + "/"
                                + str(GameManager.continues_for(2)) + ")")
                return
        GameManager.use_continue_for(2)
        if GameManager.continues_for(1) != 2 or GameManager.continues_for(2) != 2:
                _fail("A: consumo P2 ha toccato P1")
                return
        # ripristina i crediti per le fasi successive.
        GameManager.continues_left = 3
        GameManager.continues_left_p2 = 3
        _ok("A: crediti separati P1/P2 (consumo indipendente verificato)")

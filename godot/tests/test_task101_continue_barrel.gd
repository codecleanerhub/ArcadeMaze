## test_task101_continue_barrel.gd — TASK 101 (richieste utente):
##   1. "la schermata del continue che appare dopo l'ultima vita, deve
##      apparire dopo l'animazione della morte del player"
##   2. "il player raccoglie un barile per lanciarlo al boss: se il player
##      salta, il barile deve seguire il movimento del player, spostarsi in
##      alto con lui, non rimanere fermo (vale in generale per tutte le armi)"
##
## ROOT CAUSE 1: _check_death (maze) e _check_boss_death (boss room, ramo
##   1P) attendevano l'animazione solo con _is_collapsing(), che è vera
##   SOLO dopo che l'effetto è stato spawnato — ma l'effetto parte al frame
##   SUCCESSIVO alla morte (_start_pending_collapses è in testa al turno):
##   nel frame della morte la transizione CONTINUES/LOSE scattava PRIMA che
##   l'animazione iniziasse (schermata continue istantanea, corpo mai
##   accasciato). Il gate ora copre anche soul_pending / collapse_requested
##   (frame della morte incluso). Stesso gate per il game over 2P
##   (_check_all_players_out nei due controller).
## ROOT CAUSE 2: ElementalBarrel._update_carried inseguiva
##   carrier.position + CARRY_OFFSET, ma il salto alza SOLO lo sprite del
##   player (sprite.offset = -jump_offset, non position): il barile restava
##   a quota terra mentre il portatore volava. Ora il target sottrae
##   jump_offset (e il lancio parte dall'altezza visiva). Il Cannone
##   d'Assedio (SIEGE) non aveva ALCUN rendering in mano: ora è disegnato
##   con la stessa texture del pickup e segue l'arco del salto come ogni
##   arma.
##
## Check:
##   D — barile trasportato: converge sulla testa del portatore; col salto
##       (jump_offset 25) sale con lui; il lancio a mezz'aria parte
##       dall'altezza del salto (y = -18 - jump_offset)
##   E — guardie sorgente: gate completo nei due controller, gate game-over
##       2P, jump_offset in ElementalBarrel (carry+lancio), ramo SIEGE in
##       mano in Player.gd
##   C — 2P game-over GATED: _check_all_players_out NON dà LOSE mentre un
##       player è in animazione di morte (maze e boss room)
##   B — boss room 1P: morte ultima vita → _check_boss_death NON transita
##       nel frame della morte né durante l'animazione; la stanza viene
##       liberata a animazione IN CORSO (mai conclusa: zero transizioni)
##   A — maze 1P (PER ULTIMA, transita davvero): _check_death NON transita
##       nel frame della morte né durante l'animazione; SOLO a animazione
##       conclusa la chiamata porta lo stato a CONTINUES, poi si esce
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const ElementalBarrelClass = preload("res://scripts/entities/ElementalBarrel.gd")
const C = preload("res://scripts/core/GameConstants.gd")

var fails: int = 0
var _tree: SceneTree = null


func _ready() -> void:
        _tree = get_tree()
        print("[TEST] TASK 101 — continue dopo l'animazione di morte + "
                        + "barile/armi che seguono il salto")
        await _test_barrel_follows_jump()
        _test_source_guards()
        await _test_2p_gameover_gated()
        await _test_boss_room_gate()
        # A per ULTIMA: la sua ultima chiamata transita davvero verso
        # CONTINUES (cambio scena differito a fine frame) — si esce con il
        # verdetto PRIMA che il swap liberi questo nodo di test.
        await _test_maze_continue_after_animation()


func _ok(msg: String) -> void:
        print("[TEST] OK %s" % msg)


func _fail(msg: String) -> void:
        fails += 1
        print("[TEST] FALLITO %s" % msg)


# --- D: barile trasportato segue il salto (+ origine del lancio) ---
func _test_barrel_follows_jump() -> void:
        var carrier := CharacterBody2D.new()
        carrier.set_script(preload("res://tests/fake_carrier_jump.gd"))
        add_child(carrier)
        carrier.position = Vector2(500.0, 500.0)
        carrier.lives = 3
        carrier.soul_pending = false
        carrier.visible = true
        carrier.jump_offset = 0.0

        var barrel: Node2D = ElementalBarrelClass.new()
        barrel.setup(Vector2(300.0, 500.0), 0)
        add_child(barrel)
        if not barrel.pickup(carrier):
                _fail("D: pickup del barile rifiutato (stato non IDLE)")
                barrel.queue_free()
                carrier.queue_free()
                return
        # convergenza sulla testa del portatore (y = 500 - 34)
        for i in 40:
                barrel._process(1.0 / 60.0)
        var base_y: float = barrel.position.y
        if absf(base_y - 466.0) > 4.0:
                _fail("D: barile non converge sulla testa (y=%.1f, attesa ~466)" % base_y)
        # SALTO: jump_offset 25 -> il barile deve salire col portatore
        # (target y = 500 - 34 - 25 = 441; lerp 0.35 concluso in 40 tick)
        carrier.jump_offset = 25.0
        for i in 40:
                barrel._process(1.0 / 60.0)
        if barrel.position.y > 450.0:
                _fail(("D: il barile NON segue il salto (y=%.1f, attesa <=450 "
                                + "= 466-25)") % barrel.position.y)
        else:
                _ok(("D: barile trasportato sale col player (y %.1f -> %.1f, "
                                + "target 441 con salto 25px)") % [base_y, barrel.position.y])
        # LANCIO a mezz'aria: parte dall'altezza VISIVA (y = 500 - 18 - 25 = 457)
        carrier.jump_offset = 25.0
        barrel.throw_barrel(Vector2(1.0, 0.0))
        if int(barrel.state) != 2:  # 2 = THROWN
                _fail("D: throw_barrel non è scattato (state=%d)" % int(barrel.state))
        elif absf(barrel.position.y - 457.0) > 1.5:
                _fail(("D: lancio da terra invece che dal punto del salto "
                                + "(y=%.1f, attesa ~457)") % barrel.position.y)
        else:
                _ok("D: lancio a mezz'aria parte dall'altezza del salto (y=%.1f)"
                                % barrel.position.y)
        barrel.queue_free()
        carrier.queue_free()


# --- E: guardie sorgente ---
func _test_source_guards() -> void:
        var mg := _read("res://scripts/core/MainGameController.gd")
        var br := _read("res://scripts/core/BossRoomController.gd")
        var eb := _read("res://scripts/entities/ElementalBarrel.gd")
        var pl := _read("res://scripts/core/Player.gd")
        # gate completo (frame della morte incluso) nei due controller
        for src in [mg, br]:
                if src.find("or player.soul_pending") < 0 \
                                or src.find("or player.collapse_requested") < 0:
                        _fail("E: gate morte incompleto in un controller "
                                        + "(attesi soul_pending+collapse_requested)")
        # gate game-over 2P in entrambi i controller
        for src in [mg, br]:
                if src.find("p.soul_pending or p.collapse_requested") < 0:
                        _fail("E: _check_all_players_out senza gate animazioni")
        # barile: jump_offset nel follow E nel lancio
        if eb.count("carrier.jump_offset") < 2:
                _fail("E: ElementalBarrel senza jump_offset nel carry/lancio")
        # cannone d'assedio in mano + volata allineata
        if pl.find("int(current_weapon.type) == WeaponType.SIEGE") < 0:
                _fail("E: ramo SIEGE assente in _draw_equipped_weapon")
        if pl.find("return 65.0") < 0:
                _fail("E: volata SIEGE non allineata al cannone in mano (65px)")
        if fails == 0:
                _ok("E: guardie sorgente (gate x2 controller, game-over 2P, "
                                + "barile, cannone SIEGE) presenti")


# --- C: game over 2P GATED durante l'animazione di morte --------------------
# NB: si testa SOLO il gate (stato invariato finché un player è in animazione):
# lo sblocco post-animazione che porta alla transizione reale è provato dalla
# sezione A (flusso CONTINUES completo), senza ripetere qui cambi di scena.
func _test_2p_gameover_gated() -> void:
        # --- C1: maze ---
        GameManager.reset_run()
        GameManager.num_players = 2
        GameManager.current_level = 1
        GameManager.game_mode = C.GameMode.STORY
        GameManager.continues_left_p2 = 0  # P2 eliminato, NON overlay continue
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        if main.player == null or main.player2 == null:
                _fail("C: MainGame 2P non avviata")
        else:
                var state_before: int = GameManager.current_state
                var p1: CharacterBody2D = main.player
                var p2: CharacterBody2D = main.player2
                # P2: morto e sbloccato (animazione conclusa da tempo), zero
                # crediti -> eliminazione pulita.
                p2.lives = 0
                p2.soul_pending = false
                # P1: ultima vita persa, animazione IN CORSO (soul_pending,
                # nessun effetto spawnato: stato manuale deterministico)
                p1.lives = 0
                p1.soul_pending = true
                p1.collapse_requested = false
                main._check_player_elimination()  # elimina P2; P1 in attesa
                main._check_all_players_out()
                if GameManager.current_state != state_before:
                        _fail(("C1: LOSE/game-over durante l'animazione di P1 "
                                        + "(stato %d, atteso %d)")
                                        % [GameManager.current_state, state_before])
                else:
                        _ok("C1: game over 2P in attesa dell'animazione di P1 (maze)")
                # P1 resta in animazione: si libera la stanza SENZA mai
                # sbloccarlo -> nessuna transizione può partire.
        main.queue_free()
        for i in 5:
                await get_tree().physics_frame
        # --- C2: boss room ---
        GameManager.reset_run()
        GameManager.num_players = 2
        GameManager.current_level = 4
        GameManager.continues_left_p2 = 0
        var room = BossRoomScene.instantiate()
        get_tree().root.add_child(room)
        for i in 30:
                await get_tree().physics_frame
        if room.player == null or room.player2 == null:
                _fail("C2: BossRoom 2P non avviata")
        else:
                var state_before_b: int = GameManager.current_state
                var p1b: CharacterBody2D = room.player
                var p2b: CharacterBody2D = room.player2
                p2b.lives = 0
                p2b.soul_pending = false
                p1b.lives = 0
                p1b.soul_pending = true
                p1b.collapse_requested = false
                room._check_player2_elimination()
                room._check_all_players_out()
                if GameManager.current_state != state_before_b:
                        _fail(("C2: LOSE/game-over durante l'animazione in boss "
                                        + "room (stato %d, atteso %d)")
                                        % [GameManager.current_state, state_before_b])
                else:
                        _ok("C2: game over 2P in attesa dell'animazione (boss room)")
        room.queue_free()
        for i in 5:
                await get_tree().physics_frame


# --- B: boss room 1P — NESSUNA transizione finché l'animazione non finisce ---
func _test_boss_room_gate() -> void:
        GameManager.reset_run()
        GameManager.num_players = 1
        GameManager.current_level = 4
        GameManager.died_in_boss = false
        var room = BossRoomScene.instantiate()
        get_tree().root.add_child(room)
        for i in 30:
                await get_tree().physics_frame
        if room.player == null:
                _fail("B: BossRoom non avviata")
                room.queue_free()
                for i in 5:
                        await get_tree().physics_frame
                return
        var state_before: int = GameManager.current_state
        var p: CharacterBody2D = room.player
        p.lives = 1
        p.energy = 1
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.take_damage()  # ultima vita: morte definitiva, animazione richiesta
        if not p.soul_pending or p.lives != 0:
                _fail("B: morte non registrata (soul=%s lives=%d)"
                                % [p.soul_pending, p.lives])
        # FRAME DELLA MORTE (effetto NON ancora spawnato): chiamata diretta —
        # con il bug la transizione CONTINUES scattava QUI.
        room._check_boss_death()
        if GameManager.current_state != state_before:
                _fail("B: transizione nel frame della morte (stato %d, atteso %d)"
                                % [GameManager.current_state, state_before])
        # l'animazione parte e per TUTTA la sua durata lo stato non cambia
        for i in 3:
                await get_tree().physics_frame
        if room._collapses.is_empty():
                _fail("B: collasso non avviato in boss room")
        elif GameManager.current_state != state_before:
                _fail("B: transizione durante l'animazione (stato %d)"
                                % GameManager.current_state)
        else:
                # ~28 frame = ~0.47s dei ~1.16s dell'animazione: ancora IN CORSO
                for i in 25:
                        await get_tree().physics_frame
                if GameManager.current_state != state_before:
                        _fail("B: transizione durante l'animazione (stato %d)"
                                        % GameManager.current_state)
                elif room._is_collapsing(p):
                        _ok("B: boss room — morte ultima vita: animazione in "
                                        + "corso, NESSUNA transizione")
                else:
                        _fail("B: animazione già finita (frame insufficienti?)")
        # libera la stanza A ANIMAZIONE IN CORSO: il controller non vedrà mai
        # la fine dell'effetto -> nessuna transizione, la sezione A prosegue.
        room.queue_free()
        for i in 10:
                await get_tree().physics_frame


# --- A: maze 1P — CONTINUES solo DOPO l'animazione di morte ---
func _test_maze_continue_after_animation() -> void:
        GameManager.reset_run()
        GameManager.num_players = 1
        GameManager.current_level = 1
        GameManager.game_mode = C.GameMode.STORY
        var main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        for i in 30:
                await get_tree().physics_frame
        if main.player == null:
                _fail("A: MainGame non avviata")
                _finish()
                return
        var state_before: int = GameManager.current_state
        var p: CharacterBody2D = main.player
        p.lives = 1
        p.energy = 1
        p.damage_timer = 0
        p.spawn_guard_ms = 0
        p.take_damage()  # ultima vita: lives=0, animazione richiesta
        if not p.soul_pending or p.lives != 0:
                _fail("A: morte non registrata (soul=%s lives=%d)"
                                % [p.soul_pending, p.lives])
        # FRAME DELLA MORTE: chiamata diretta a _check_death con l'effetto NON
        # ancora avviato — con il bug la schermata continue partiva QUI,
        # tagliando l'animazione di morte del tutto.
        main._check_death()
        if GameManager.current_state != state_before:
                _fail(("A: continue nel frame della morte, prima dell'animazione "
                                + "(stato %d)") % GameManager.current_state)
        # l'animazione parte e per TUTTA la sua durata lo stato non cambia
        for i in 3:
                await get_tree().physics_frame
        if main._collapses.is_empty():
                _fail("A: collasso non avviato")
        elif GameManager.current_state != state_before:
                _fail("A: transizione durante l'animazione (stato %d)"
                                % GameManager.current_state)
        else:
                _ok("A: morte ultima vita -> animazione avviata, stato invariato")
        # attende la FINE dell'animazione (max ~5s headless): la coroutine si
        # riprende sul physics_frame PRIMA che il controller aggiorni il frame
        # -> nessuna transizione automatica è ancora avvenuta.
        var guard: int = 0
        while main._is_collapsing(p) and guard < 300:
                await get_tree().physics_frame
                guard += 1
        if main._is_collapsing(p):
                _fail("A: animazione mai terminata (guard 300)")
        elif p.soul_pending or p.lives != 0:
                _fail("A: stato post-animazione errato (soul=%s lives=%d)"
                                % [p.soul_pending, p.lives])
        else:
                # SOLO ORA la transizione è permessa: chiamata diretta.
                main._check_death()
                if GameManager.current_state == C.GameState.CONTINUES:
                        _ok(("A: animazione conclusa (%d frame) -> SOLO ORA "
                                        + "CONTINUES") % guard)
                else:
                        _fail("A: CONTINUES atteso dopo l'animazione (stato %d)"
                                        % GameManager.current_state)
        _finish()


func _finish() -> void:
        if fails > 0:
                print("[TEST] ESITO: FALLITO (%d errori)" % fails)
                _tree.quit(1)
        else:
                print("[TEST] ESITO: TUTTI PASSATI")
                _tree.quit(0)


func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var txt: String = f.get_as_text()
        f.close()
        return txt

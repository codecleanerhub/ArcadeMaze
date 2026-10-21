## test_friendly_fire.gd — Test funzionale runtime (headless) del FUOCO AMICO
## con trasferimento anima (Task 18, richiesta utente):
##   A. COLPO NON FATALE P1->P2: -1 energia, vite invariate, niente anima.
##   B. COLPO FATALE P1->P2 (ultima energia): P2 perde una vita, resta
##      congelata (soul_pending), corpo nascosto, effetto SoulTransferEffect
##      presente; l'anima vola verso P1 e gli ricarica COMPLETAMENTE
##      l'energia; P2 respawn alla cella di partenza.
##   C. BIDIREZIONALITA' P2->P1: colpo non fatale + colpo fatale speculari.
##   D. 1P: il fuoco amico NON attivo senza il secondo player.
##   E. INVULNERABILITA': i colpi a bersaglio invulnerabile passano attraverso.
##   F. BOSS ROOM: stessa meccanica durante lo scontro col boss.
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const SoulFx = preload("res://scripts/entities/SoulTransferEffect.gd")

var main: Node2D = null
var boss_room: Node2D = null
var phase: int = 0
var t: float = 0.0
var phase_t: float = 0.0
var armed: bool = false   # true = sparo/verify di questa fase gia' eseguito
var failures: Array = []
# Celle corridoio sicure (determinate a runtime sul maze generato):
# i proiettili player MUOIONO nelle celle muro (wall-culling in
# update_player), quindi il test posiziona i player solo su corridoi.
var pos_a: Vector2 = Vector2.ZERO
var pos_b: Vector2 = Vector2.ZERO

# Posizione di respawn attesa (reset_position: cella (1,1) + barra UI,
# TILE_SIZE 64, UI_HEIGHT 80 — mirror Player.gd).
const RESPAWN_POS := Vector2(1.5 * 64.0, 1.5 * 64.0 + 80.0)


func _ready() -> void:
        GameManager.num_players = 2
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 2P per fuoco amico...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _next(next_phase: int) -> void:
        phase = next_phase
        phase_t = 0.0
        armed = false


func _ready_main() -> bool:
        return main != null and main.is_node_ready()


func _ready_boss() -> bool:
        return boss_room != null and boss_room.is_node_ready()


# Spara un proiettile "virtuale" di `shooter` che nasce ESATTAMENTE addosso a
# `target` (collisione garantita al primo frame del check FF).
func _fake_shot(shooter: CharacterBody2D, target: CharacterBody2D) -> void:
        shooter.projectiles.append({
                "pos": target.get_pixel_pos(),
                "dir": Vector2(1.0, 0.0),
                "power": 1,
                "active": true,
                "type": 0,
        })


# Azzera il timer Hurry Up! (con tutti i nemici morti, dopo 10s spawnavano i
# fantasmi immortali che assorbono i proiettili e disturberebbero il test).
func _keep_hurry_up_quiet() -> void:
        if main != null and is_instance_valid(main):
                main._since_last_treasure_ms = 0.0


func _has_soul_effect(root_node: Node2D) -> bool:
        for ch in root_node.get_children():
                if ch is Node2D and ch.get_script() == SoulFx:
                        return true
        return false


func _physics_process(delta: float) -> void:
        t += delta
        phase_t += delta
        if t > 30.0:
                _fail("timeout globale del test (30s)")
                get_tree().quit(1)
                return
        match phase:
                0:
                        # --- A0: boot 2P, nemici fuori gioco, posizioni su corridoi ---
                        if _ready_main() and phase_t > 1.2:
                                var p2: CharacterBody2D = main.player2
                                if not p2.visible:
                                        _fail("A0: P2 non attiva in 2P")
                                # Uccide tutti i nemici: il test deve essere
                                # deterministico (nessuna interferenza IA).
                                for e in main.spawner.enemies:
                                        e.take_damage(99999)
                                # TASK 38 (spawn guard): i player nascono con 3s
                                # di immortalita' — azzerata perche' il fuoco
                                # amico del test deve colpire DA SUBITO.
                                main.player.spawn_guard_ms = 0
                                main.player2.spawn_guard_ms = 0
                                # Rimuove gli item a terra (medikit/pozione
                                # potrebbero alterare l'energia al pickup).
                                for item in main.collectibles_node.get_children():
                                        item.queue_free()
                                # Cella A = spawn classico (1,1), sempre corridoio.
                                pos_a = Vector2(1.5 * 64.0, 1.5 * 64.0 + 80.0)
                                # Cella B = primo corridoio trovato a >= 5 colonne
                                # di distanza (riga per riga).
                                pos_b = Vector2.ZERO
                                var found_b: bool = false
                                for r in range(1, 14):
                                        if found_b:
                                                break
                                        for c in range(6, 15):
                                                if not main.maze.is_wall(c, r):
                                                        pos_b = Vector2(c * 64.0 + 32.0, r * 64.0 + 32.0 + 80.0)
                                                        found_b = true
                                                        break
                                if not found_b:
                                        _fail("A0: nessuna cella corridoio trovata per pos_b")
                                        pos_b = pos_a
                                main.player.set_position_abs(pos_a.x, pos_a.y)
                                p2.set_position_abs(pos_b.x, pos_b.y)
                                _keep_hurry_up_quiet()
                                print("[TEST] OK A0: boot 2P, nemici/item neutralizzati, corridoi: ",
                                                pos_a, " / ", pos_b)
                                _next(1)
                1:
                        # --- A: colpo non fatale P1 -> P2 ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                var p2a: CharacterBody2D = main.player2
                                p2a.energy = 5
                                p2a.damage_timer = 0
                                _fake_shot(main.player, p2a)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.35:
                                var p2b: CharacterBody2D = main.player2
                                if p2b.energy != 4:
                                        _fail("A: energia P2 dopo colpo non fatale = " + str(p2b.energy) + ", attesa 4")
                                elif p2b.lives != 3:
                                        _fail("A: P2 ha perso vite su colpo non fatale! lives = " + str(p2b.lives))
                                elif p2b.soul_pending:
                                        _fail("A: P2 in soul_pending su colpo non fatale?!")
                                else:
                                        print("[TEST] OK A: colpo non fatale P1->P2 (-1 energia, vite intatte)")
                                _next(2)
                2:
                        # --- B1: colpo FATALE P1 -> P2 ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                var p1b: CharacterBody2D = main.player
                                var p2b: CharacterBody2D = main.player2
                                p1b.energy = 2  # per verificare la ricarica totale
                                p2b.energy = 1  # ultima energia: colpo fatale
                                p2b.damage_timer = 0
                                _fake_shot(p1b, p2b)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.35:
                                var p2c: CharacterBody2D = main.player2
                                if p2c.lives != 2:
                                        _fail("B1: P2 non ha perso la vita (lives = " + str(p2c.lives) + ", attese 2)")
                                elif not p2c.soul_pending:
                                        _fail("B1: P2 non congelata in soul_pending dopo morte da fuoco amico")
                                elif p2c.sprite != null and p2c.sprite.visible:
                                        _fail("B1: sprite di P2 non nascosto durante il transfer anima")
                                elif not _has_soul_effect(main):
                                        _fail("B1: nessun effetto SoulTransferEffect nella scena")
                                elif p2c.energy != p2c.max_energy:
                                        _fail("B1: energia P2 non ripristinata al max dopo la morte")
                                else:
                                        print("[TEST] OK B1: morte da fuoco amico: vita persa, corpo congelato, anima in volo")
                                _next(3)
                3:
                        # --- B2: l'anima raggiunge P1: ricarica COMPLETA + respawn P2 ---
                        if not _ready_main():
                                return
                        _keep_hurry_up_quiet()
                        if main.player2.soul_pending:
                                if phase_t > 4.0:
                                        _fail("B2: l'anima non ha mai raggiunto P1 (4s)")
                                        _next(4)
                                return
                        var p1c: CharacterBody2D = main.player
                        var p2d: CharacterBody2D = main.player2
                        if p1c.energy != p1c.max_energy:
                                _fail("B2: P1 non ricaricato al massimo (energy = " + str(p1c.energy) + ")")
                        elif p2d.lives != 2:
                                _fail("B2: vite P2 cambiate dal transfer (lives = " + str(p2d.lives) + ")")
                        elif p2d.sprite != null and not p2d.sprite.visible:
                                _fail("B2: sprite di P2 non ripristinato al respawn")
                        elif p2d.get_pixel_pos().distance_to(RESPAWN_POS) > 1.0:
                                _fail("B2: P2 non respawnata alla cella di partenza: " + str(p2d.get_pixel_pos()))
                        else:
                                print("[TEST] OK B2: anima consegnata: P1 energia FULL, P2 respawnata")
                        _next(4)
                4:
                        # --- C1: colpo non fatale P2 -> P1 (bidirezionalita') ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                var p1d: CharacterBody2D = main.player
                                # P1 e' respawnato su (1,1) dove sta P2:
                                # lo separiamo di nuovo sul corridoio B.
                                p1d.set_position_abs(pos_b.x, pos_b.y)
                                p1d.energy = 4
                                p1d.damage_timer = 0
                                main.player2.damage_timer = 0
                                _fake_shot(main.player2, p1d)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.35:
                                var p1e: CharacterBody2D = main.player
                                if p1e.energy != 3:
                                        _fail("C1: energia P1 dopo colpo P2 = " + str(p1e.energy) + ", attesa 3")
                                elif p1e.lives != 3:
                                        _fail("C1: P1 ha perso vite su colpo non fatale P2")
                                else:
                                        print("[TEST] OK C1: fuoco amico bidirezionale (P2 -> P1, -1 energia)")
                                _next(5)
                5:
                        # --- C2a: colpo FATALE P2 -> P1 ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                var p1f: CharacterBody2D = main.player
                                var p2e: CharacterBody2D = main.player2
                                p1f.set_position_abs(pos_b.x, pos_b.y)
                                p1f.energy = 1  # ultima energia
                                p1f.damage_timer = 0
                                p2e.energy = 2  # per verificare la ricarica totale
                                _fake_shot(p2e, p1f)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.35:
                                var p1g: CharacterBody2D = main.player
                                if p1g.lives != 2:
                                        _fail("C2: P1 non ha perso la vita (lives = " + str(p1g.lives) + ")")
                                elif not p1g.soul_pending:
                                        _fail("C2: P1 non congelato in soul_pending dopo morte da fuoco amico")
                                elif not _has_soul_effect(main):
                                        _fail("C2: nessun effetto anima per P1 ucciso da P2")
                                else:
                                        print("[TEST] OK C2a: P1 ucciso da P2: corpo congelato, anima in volo")
                                _next(6)
                6:
                        # --- C2b: consegna anima -> P2 energia FULL, P1 respawn ---
                        if not _ready_main():
                                return
                        _keep_hurry_up_quiet()
                        if main.player.soul_pending:
                                if phase_t > 4.0:
                                        _fail("C2b: timeout attesa anima P1->P2 (4s)")
                                        _next(7)
                                return
                        var p2f: CharacterBody2D = main.player2
                        var p1h: CharacterBody2D = main.player
                        if p2f.energy != p2f.max_energy:
                                _fail("C2b: P2 non ricaricato al massimo (energy = " + str(p2f.energy) + ")")
                        elif p1h.lives != 2:
                                _fail("C2b: vite P1 sbagliate dopo transfer (lives = " + str(p1h.lives) + ")")
                        elif p1h.get_pixel_pos().distance_to(RESPAWN_POS) > 1.0:
                                _fail("C2b: P1 non respawnato: " + str(p1h.get_pixel_pos()))
                        else:
                                print("[TEST] OK C2b: anima consegnata: P2 energia FULL, P1 respawnato")
                        _next(7)
                7:
                        # --- D: in 1P il fuoco amico NON attivo ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                GameManager.num_players = 1
                                var p2g: CharacterBody2D = main.player2
                                main.player.set_position_abs(pos_b.x, pos_b.y)
                                p2g.energy = 1
                                p2g.damage_timer = 0
                                main.player.damage_timer = 0
                                _fake_shot(main.player, p2g)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.6:
                                var p2h: CharacterBody2D = main.player2
                                if p2h.energy != 1:
                                        _fail("D: P2 colpita anche in 1P (energy = " + str(p2h.energy) + ")")
                                elif p2h.soul_pending:
                                        _fail("D: transfer anima partito in 1P?!")
                                else:
                                        print("[TEST] OK D: in 1P il fuoco amico resta disattivo")
                                GameManager.num_players = 2  # ripristino per le fasi successive
                                _next(8)
                8:
                        # --- E: bersaglio invulnerabile -> il colpo passa attraverso ---
                        if not _ready_main():
                                return
                        if not armed:
                                armed = true
                                var p2i: CharacterBody2D = main.player2
                                p2i.energy = 1
                                p2i.damage_timer = 1000  # ~1s di invulnerabilita'
                                main.player.damage_timer = 0
                                _fake_shot(main.player, p2i)
                                _keep_hurry_up_quiet()
                                return
                        if phase_t > 0.5:
                                var p2j: CharacterBody2D = main.player2
                                if p2j.energy != 1:
                                        _fail("E: P2 colpita nonostante invulnerabilita' (energy = " + str(p2j.energy) + ")")
                                elif p2j.soul_pending:
                                        _fail("E: transfer anima partito su bersaglio invulnerabile?!")
                                elif p2j.lives != 2:
                                        _fail("E: vite P2 cambiate (lives = " + str(p2j.lives) + ")")
                                else:
                                        print("[TEST] OK E: colpo a bersaglio invulnerabile: passa attraverso")
                                _next(9)
                9:
                        # --- F1: fuoco amico in BOSS ROOM (colpo fatale) ---
                        if boss_room == null:
                                if phase_t > 0.1:
                                        boss_room = BossRoomScene.instantiate()
                                        get_tree().root.add_child.call_deferred(boss_room)
                                        phase_t = 0.0
                                return
                        if _ready_boss() and phase_t > 1.0:
                                var brp1: CharacterBody2D = boss_room.player
                                var brp2: CharacterBody2D = boss_room.player2
                                # Congela il loop del boss (nessuna interferenza):
                                # l'effetto anima gira comunque (_process proprio,
                                # albero non in pausa).
                                boss_room.is_paused = true
                                brp2.visible = true
                                brp1.set_position_abs(400.0, 500.0)
                                brp2.set_position_abs(700.0, 500.0)
                                brp1.energy = 2
                                brp2.energy = 1
                                # TASK 38 (spawn guard): l'ingresso in boss
                                # room riarma la guardia di nascita — azzerata
                                # perche' l'F1 verifica il colpo fatale reale.
                                brp1.spawn_guard_ms = 0
                                brp2.spawn_guard_ms = 0
                                brp1.damage_timer = 0
                                brp2.damage_timer = 0
                                _fake_shot(brp1, brp2)
                                boss_room._check_friendly_fire_projectiles()
                                if brp2.lives != 2:
                                        _fail("F1: P2 non ha perso la vita in boss room (lives = " + str(brp2.lives) + ")")
                                elif not brp2.soul_pending:
                                        _fail("F1: P2 non congelata in boss room dopo morte da fuoco amico")
                                elif not _has_soul_effect(boss_room):
                                        _fail("F1: nessun effetto anima in boss room")
                                else:
                                        print("[TEST] OK F1: colpo fatale in boss room: anima in volo verso P1")
                                _next(10)
                10:
                        # --- F2: consegna anima in boss room ---
                        if not _ready_boss():
                                return
                        if boss_room.player2.soul_pending:
                                if phase_t > 4.0:
                                        _fail("F2: l'anima non ha mai raggiunto P1 in boss room (4s)")
                                        _next(11)
                                return
                        var brp1b: CharacterBody2D = boss_room.player
                        if brp1b.energy != brp1b.max_energy:
                                _fail("F2: P1 non ricaricato al massimo in boss room (energy = " + str(brp1b.energy) + ")")
                        else:
                                print("[TEST] OK F2: boss room: anima consegnata, P1 energia FULL, P2 respawnata")
                        _next(11)
                11:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST FUOCO AMICO / ANIMA SUPERATI ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)

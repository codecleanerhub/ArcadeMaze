## test_stamina_weapons.gd — Test funzionale runtime (headless) delle nuove
## meccaniche richieste:
##   A. STAMINA (salti): max 2 SALTI CONSECUTIVI (TASK 23: richiesto
##      dall'utente — prima erano 3); ogni salto consuma 1/2; il 3° salto
##      ravvicinato è BLOCCATO (click a vuoto); dopo il 2° la barra è vuota
##      ("stanco") e non si salta finché non è piena; con pause distese i
##      salti riescono; al respawn barra piena.
##   B. POZIONE VERDE: durata 9s (5+4 richiesti): timer e fine effetto.
##   C. BOSS ROOM ARMI: con P1 a zero munizioni e armi a terra finite appare
##      UN ALTRO SET (e si ripete: "finché il boss non è terminato").
##      In 1P il respawn ora funziona (bug: p2_empty restava false);
##      in 2P serve che TUTTI i player vivi siano a zero.
##   D. AUDIO: stream STAMINA_CLICK generato; tema calice Cavalleria
##      Rusticana della durata esatta dell'effetto (9.5s).
extends Node

const MainGameScene = preload("res://scenes/MainGame.tscn")
const BossRoomScene = preload("res://scenes/BossRoom.tscn")
const PlayerScript = preload("res://scripts/core/Player.gd")

var main: Node2D = null
var boss_room: Node2D = null
var phase: int = 0
var t: float = 0.0
var failures: Array = []

# Stato del test stamina
var chain_results: Array = []
var chain_done: bool = false
var fourth_tried: bool = false
var recharge_t0: float = -1.0
var paced_results: Array = []
var paced_wait_until: float = 0.0
var paced_next: int = 0


func _ready() -> void:
        GameManager.num_players = 1
        main = MainGameScene.instantiate()
        get_tree().root.add_child.call_deferred(main)
        print("[TEST] boot MainGame 1P...")


func _fail(msg: String) -> void:
        failures.append(msg)
        print("[TEST FAIL] ", msg)


func _ready_main() -> bool:
        return main != null and main.is_node_ready()


func _ready_boss() -> bool:
        return boss_room != null and boss_room.is_node_ready()


func _physics_process(delta: float) -> void:
        t += delta
        match phase:
                0:
                        # --- A1: stato iniziale: stamina piena, non stanco ---
                        if _ready_main() and t > 1.0:
                                var p = main.player
                                if absf(p.stamina - 1.0) > 0.001:
                                        _fail("A1: stamina iniziale = " + str(p.stamina) + ", attesa 1.0")
                                else:
                                        print("[TEST] OK A1: stamina iniziale piena")
                                if p.stamina_exhausted:
                                        _fail("A1: player già esausto all'avvio?!")
                                phase = 1
                1:
                        # --- A2: catena di 2 salti ravvicinati (TASK 23) ---
                        # Salta appena atterra (stesso frame/frames ravvicinati):
                        # è la condizione "salti consecutivi".
                        if not _ready_main():
                                return
                        var p = main.player
                        if not p.is_jumping():
                                var res: bool = p.activate_jump()
                                chain_results.append(res)
                        if chain_results.size() >= 2 and not p.is_jumping() and t > 2.0:
                                # --- A3: verifica dei 2 salti consecutivi ---
                                if not chain_results[0] or not chain_results[1]:
                                        _fail("A3: salti consecutivi rifiutati: " + str(chain_results))
                                elif p.stamina > 0.0001:
                                        _fail("A3: dopo 2 salti la barra non è vuota: " + str(p.stamina))
                                elif not p.stamina_exhausted:
                                        _fail("A3: dopo 2 salti consecutivi il player non è 'stanco'")
                                else:
                                        print("[TEST] OK A3: 2 salti consecutivi OK, barra vuota, player stanco")
                                # --- A4: 3° salto immediato BLOCCATO (TASK 23) ---
                                var blocked: bool = p.activate_jump()
                                if blocked:
                                        _fail("A4: il 3° salto consecutivo è partito (doveva essere bloccato)")
                                elif p.is_jumping():
                                        _fail("A4: il 3° salto bloccato ha comunque avviato il salto")
                                else:
                                        print("[TEST] OK A4: 3° salto bloccato (click a vuoto), player fermo")
                                recharge_t0 = t
                                phase = 2
                2:
                        # --- A5: da esausto non si salta finché la barra non è
                        # COMPLETAMENTE ricaricata (delay 720ms + 2400ms) ---
                        if not _ready_main():
                                return
                        var p = main.player
                        if p.stamina >= 1.0:
                                if p.stamina_exhausted:
                                        _fail("A5: barra piena ma ancora esausto")
                                else:
                                        print("[TEST] OK A5: ricarica completa in ",
                                                        "%.1f" % ((t - recharge_t0) * 1000.0),
                                                        "ms, player non più stanco")
                                # A metà ricarica (ora è piena): svuotiamo di
                                # nuovo e verifichiamo il blocco intermedio.
                                p.stamina = 0.2
                                p.stamina_exhausted = false
                                if p.activate_jump():
                                        _fail("A5: salto partito con stamina 0.2 (< 1/2)")
                                else:
                                        print("[TEST] OK A5: con 0.2 di barra (< 1/2) il salto è rifiutato")
                                p.stamina = 1.0
                                # --- A6: dopo la ricarica si salta di nuovo ---
                                if not p.activate_jump():
                                        _fail("A6: dopo la ricarica completa il salto non riparte")
                                else:
                                        print("[TEST] OK A6: dopo la ricarica il salto riparte")
                                paced_next = 0
                                paced_results.clear()
                                # Pacing 2.5s: salto (0.67s) + delay ricarica
                                # (0.72s) + ricarica piena di un terzo
                                # (0.8s) → ritmo sostenibile.
                                paced_wait_until = t + 2.5
                                phase = 3
                        elif t - recharge_t0 > 8.0:
                                _fail("A5: ricarica completa MAI raggiunta (stamina "
                                                + str(p.stamina) + ")")
                                phase = 9
                3:
                        # --- A7: salti distesi (1.5s tra loro): riescono sempre ---
                        if not _ready_main():
                                return
                        var p = main.player
                        if t >= paced_wait_until and not p.is_jumping():
                                var res: bool = p.activate_jump()
                                paced_results.append(res)
                                paced_next += 1
                                if paced_next >= 3:
                                        if not paced_results[0] or not paced_results[1] \
                                                        or not paced_results[2]:
                                                _fail("A7: salti distesi rifiutati: " + str(paced_results))
                                        elif p.stamina_exhausted:
                                                _fail("A7: salti distesi hanno esaurito la barra?!")
                                        else:
                                                print("[TEST] OK A7: 3 salti distesi OK, barra a ",
                                                                "%.2f" % p.stamina,
                                                                " (si ricarica se non si salta)")
                                        # --- A8: reset_position = gambe riposate ---
                                        p.stamina = 0.1
                                        p.stamina_exhausted = true
                                        p.reset_position()
                                        if absf(p.stamina - 1.0) > 0.001 or p.stamina_exhausted:
                                                _fail("A8: dopo respawn la stamina non è piena")
                                        else:
                                                print("[TEST] OK A8: al respawn la stamina è piena")
                                        # --- A9: colori barra stamina (Task 37; TASK 96: piena VERDE) ---
                                        # VERDE piena (2 salti disponibili; TASK 96, era rosa), ARANCIONE
                                        # dopo il 1° salto (1 disponibile), ROSSA dopo
                                        # il 2° (0 disponibili). Colore = salti usati.
                                        var st_hud = main.hud
                                        if st_hud == null:
                                                _fail("A9: HUD non trovata in MainGame")
                                        else:
                                                var c_pink: Color = st_hud._stamina_fill_color(1.0)
                                                var c_orange: Color = st_hud._stamina_fill_color(0.5)
                                                var c_red: Color = st_hud._stamina_fill_color(0.0)
                                                var c_mid: Color = st_hud._stamina_fill_color(0.75)
                                                # TASK 96: piena = VERDE (era ROSA — feedback utente)
                                                if c_pink.g <= c_pink.r or c_pink.b > 0.5:
                                                        _fail("A9: barra piena non VERDE: " + str(c_pink))
                                                else:
                                                        print("[TEST] OK A9a: barra piena = VERDE ", str(c_pink))
                                                if c_orange.g <= c_orange.b or c_orange.r < 0.9:
                                                        _fail("A9: metà barra non ARANCIONE: " + str(c_orange))
                                                else:
                                                        print("[TEST] OK A9b: dopo il 1° salto = ARANCIONE ", str(c_orange))
                                                if c_red.r < 0.7 or c_red.g > 0.3 or c_red.b > 0.3:
                                                        _fail("A9: barra svuotata non ROSSA: " + str(c_red))
                                                else:
                                                        print("[TEST] OK A9c: dopo il 2° salto = ROSSO ", str(c_red))
                                                if c_mid.g <= c_mid.b:
                                                        _fail("A9: a 0.75 atteso ARANCIONE (1 salto disponibile): " + str(c_mid))
                                                else:
                                                        print("[TEST] OK A9d: 0.75 = ARANCIONE (1 salto disponibile)")
                                        # --- B: pozione verde 9s (5+4) ---
                                        if PlayerScript.GHOST_MODE_DURATION_MS != 9000:
                                                _fail("B: GHOST_MODE_DURATION_MS = "
                                                                + str(PlayerScript.GHOST_MODE_DURATION_MS)
                                                                + ", attesi 9000 (5+4)")
                                        p.start_ghost_mode()
                                        if p.ghost_timer_ms != 9000:
                                                _fail("B: timer pozione = " + str(p.ghost_timer_ms)
                                                                + ", attesi 9000")
                                        elif not p.is_ghost():
                                                _fail("B: modalità fantasma non attiva dopo la pozione")
                                        else:
                                                print("[TEST] OK B: pozione verde = 9s (5+4 richiesti)")
                                        # Fine effetto simulata in avanamento accelerato
                                        p.update_player(main.maze, false, 8900.0)
                                        if not p.is_ghost():
                                                _fail("B: l'effetto fantasama finito troppo presto (a 8.9s)")
                                        p.update_player(main.maze, false, 300.0)
                                        if p.is_ghost():
                                                _fail("B: l'effetto fantasama non finisce a 9.2s")
                                        else:
                                                print("[TEST] OK B: effetto fantasma attivo a 8.9s, finito a 9.2s")
                                        # --- D: audio ---
                                        if AudioManager:
                                                var click_stream = AudioManager._sfx_streams[
                                                                AudioManager.SoundType.STAMINA_CLICK]
                                                if click_stream == null:
                                                        _fail("D: stream STAMINA_CLICK non generato")
                                                else:
                                                        print("[TEST] OK D1: stream STAMINA_CLICK presente (",
                                                                        click_stream.data.size(), " bytes)")
                                                # TASK 93: _gen_epic_chalice rimosso
                                                # (musica del calice eliminata) —
                                                # ora si testa il nuovo SFX epico
                                                # del calice (CHALICE_POWER).
                                                var ch: PackedFloat32Array = AudioManager._sfx_chalice_power()
                                                var expect_len: int = int(44100 * 2.2)
                                                if ch.size() != expect_len:
                                                        _fail("D: SFX calice lungo " + str(ch.size())
                                                                        + " campioni, attesi " + str(expect_len))
                                                else:
                                                        print("[TEST] OK D2: SFX CHALICE_POWER = 2.2s esatti (one-shot)")
                                                var peak: float = 0.0
                                                var energy: float = 0.0
                                                for i in range(0, ch.size(), 997):
                                                        var av: float = absf(ch[i])
                                                        if av > peak:
                                                                peak = av
                                                        energy += av * av
                                                if peak > 0.87:
                                                        _fail("D: SFX calice in clipping (peak " + str(peak) + ")")
                                                else:
                                                        print("[TEST] OK D3: SFX calice peak ", "%.3f" % peak, " (no clip)")
                                        # Passiamo alla boss room
                                        main.queue_free()
                                        phase = 4
                                        t = 0.0
                                else:
                                        paced_wait_until = t + 2.5
                4:
                        # --- C: boss room 1P — respawn set di armi ---
                        if t < 0.6:
                                return
                        GameManager.num_players = 1
                        boss_room = BossRoomScene.instantiate()
                        get_tree().root.add_child.call_deferred(boss_room)
                        print("[TEST] boot BossRoom 1P...")
                        phase = 5
                        t = 0.0
                5:
                        if not _ready_boss() or t < 1.5:
                                return
                        var br = boss_room
                        # C1: set iniziale di armi a terra
                        var set0: int = br.boss_room_weapons.size()
                        if set0 < 1:
                                _fail("C1: nessuna arma a terra all'avvio della boss room")
                        else:
                                print("[TEST] OK C1: set iniziale di armi: ", set0)
                        # C2: P1 a zero munizioni MA armi a terra presenti → NO respawn
                        br.player.current_weapon["ammo"] = 0
                        br._check_softlock()
                        if br.boss_room_weapons.size() != set0:
                                _fail("C2: respawn con armi ancora a terra (doveva aspettare)")
                        else:
                                print("[TEST] OK C2: con armi ancora a terra nessun respawn")
                        # C3: raccogli TUTTE le armi a terra (teleport pickup) e
                        # poi a zero munizioni → NUOVO SET
                        br._pickup_all_floor_weapons_for_test()
                        if not br.boss_room_weapons.is_empty():
                                _fail("C3: setup test: armi a terra non raccolte")
                        br.player.current_weapon["ammo"] = 0
                        br._check_softlock()
                        if br.boss_room_weapons.size() < 1:
                                _fail("C3: 1P a zero munizioni + armi finite: NESSUN nuovo set (bug del p2_empty false)")
                        else:
                                print("[TEST] OK C3: 1P senza munizioni e armi finite → NUOVO SET di ",
                                                br.boss_room_weapons.size(), " armi")
                        # C4: il set si ripete (finché il boss non è terminato)
                        br._pickup_all_floor_weapons_for_test()
                        br.player.current_weapon["ammo"] = 0
                        br._check_softlock()
                        if br.boss_room_weapons.size() < 1:
                                _fail("C4: il secondo set di armi NON è riapparso")
                        else:
                                print("[TEST] OK C4: un ALTRO set riappare (finché il boss vive)")
                        # --- C in 2P: respawn solo quando TUTTI i vivi sono a zero ---
                        boss_room.queue_free()
                        GameManager.num_players = 2
                        boss_room = BossRoomScene.instantiate()
                        get_tree().root.add_child.call_deferred(boss_room)
                        print("[TEST] boot BossRoom 2P...")
                        phase = 6
                        t = 0.0
                6:
                        if not _ready_boss() or t < 1.5:
                                return
                        var br2 = boss_room
                        br2._pickup_all_floor_weapons_for_test()
                        # P1 a zero, P2 con munizioni → NO respawn
                        br2.player.current_weapon["ammo"] = 0
                        br2.player2.current_weapon["ammo"] = 10
                        br2._check_softlock()
                        if not br2.boss_room_weapons.is_empty():
                                _fail("C5: 2P respawn con P2 ancora armato (doveva servire TUTTI a zero)")
                        else:
                                print("[TEST] OK C5: 2P con P2 armato: nessun respawn")
                        # Anche P2 a zero → respawn
                        br2.player2.current_weapon["ammo"] = 0
                        br2._check_softlock()
                        if br2.boss_room_weapons.is_empty():
                                _fail("C5: 2P entrambi a zero + armi finite: nessun respawn")
                        else:
                                print("[TEST] OK C5: 2P entrambi senza munizioni → nuovo set")
                        # P2 eliminato: il gate dipende solo da P1
                        br2._pickup_all_floor_weapons_for_test()
                        br2.player.current_weapon["ammo"] = 0
                        br2.player2.visible = false
                        br2._check_softlock()
                        if br2.boss_room_weapons.is_empty():
                                _fail("C6: con P2 eliminato il respawn non scatta (p2_empty doveva essere true)")
                        else:
                                print("[TEST] OK C6: P2 eliminato → il gate torna su P1 (respawn OK)")
                        phase = 9
                9:
                        if failures.is_empty():
                                print("[TEST] ==== TUTTI I TEST STAMINA + POZIONE + ARMI BOSS + AUDIO SUPERATI ====")
                                get_tree().quit(0)
                        else:
                                print("[TEST] ==== FALLITI ", failures.size(), " test ====")
                                for f in failures:
                                        print("[TEST FAIL] ", f)
                                get_tree().quit(1)
